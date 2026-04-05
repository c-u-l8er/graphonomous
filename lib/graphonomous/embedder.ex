defmodule Graphonomous.Embedder do
  @moduledoc """
  Embedding runtime for Graphonomous.

  Backends (tried in order for `:auto`):
  1. **Bumblebee** — Nx.Serving with sentence-transformers (BERT-family models)
  2. **ONNX** — Ortex + HuggingFace Tokenizers for any ONNX model (e.g. nomic-embed-text-v2-moe)
  3. **Fallback** — deterministic local hashing (no ML, always works)

  Task prefixes:
  - Some models (e.g. nomic-embed-text-v1.5) require task-specific prefixes.
    Configure via :embedding_task_prefixes map, e.g.
    %{query: "search_query: ", document: "search_document: "}
  """

  use GenServer

  require Logger

  @default_model_id "sentence-transformers/all-MiniLM-L6-v2"
  @default_dimension 384
  @default_timeout 15_000
  @default_batch_size 8
  @default_onnx_sequence_length 64

  @onnx_cache_base Path.join([System.user_home() || "/tmp", ".cache", "graphonomous", "onnx"])

  @type backend :: :bumblebee | :onnx | :fallback | :warming
  @type embedding :: [float()]
  @type task :: :query | :document | nil

  @type state :: %{
          backend: backend(),
          serving: term() | nil,
          onnx_model: term() | nil,
          tokenizer: term() | nil,
          model_id: String.t(),
          dimension: pos_integer(),
          warmup_in_progress: boolean(),
          task_prefixes: map() | nil,
          onnx_sequence_length: pos_integer()
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns an embedding vector for a single text input.

  Options:
    - `:timeout` — GenServer call timeout (default: #{@default_timeout}ms)
    - `:task` — `:query` | `:document` | `nil` — applies model-specific task prefix
  """
  @spec embed(String.t(), keyword()) :: {:ok, embedding()} | {:error, term()}
  def embed(text, opts \\ []) when is_binary(text) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    task = Keyword.get(opts, :task)
    GenServer.call(__MODULE__, {:embed, text, task}, timeout)
  end

  @doc """
  Returns embeddings for multiple text inputs.

  Options:
    - `:timeout` — GenServer call timeout
    - `:task` — `:query` | `:document` | `nil`
  """
  @spec embed_many([String.t()], keyword()) :: {:ok, [embedding()]} | {:error, term()}
  def embed_many(texts, opts \\ []) when is_list(texts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    task = Keyword.get(opts, :task)
    GenServer.call(__MODULE__, {:embed_many, texts, task}, timeout)
  end

  @doc """
  Returns a little-endian float32 binary embedding suitable for SQLite BLOB storage.

  Options:
    - `:task` — `:query` | `:document` | `nil`
  """
  @spec embed_binary(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def embed_binary(text, opts \\ []) when is_binary(text) do
    with {:ok, vector} <- embed(text, opts) do
      {:ok, to_f32_binary(vector)}
    end
  end

  @doc """
  Returns little-endian float32 binary embeddings for multiple texts.
  Uses true batch inference when the Bumblebee or ONNX backend is active.

  Options:
    - `:task` — `:query` | `:document` | `nil`
  """
  @spec embed_many_binary([String.t()], keyword()) :: {:ok, [binary()]} | {:error, term()}
  def embed_many_binary(texts, opts \\ []) when is_list(texts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout * length(texts))
    task = Keyword.get(opts, :task)
    GenServer.call(__MODULE__, {:embed_many_binary, texts, task}, timeout)
  end

  @doc """
  Runtime info for observability.
  """
  @spec info() :: map()
  def info do
    GenServer.call(__MODULE__, :info)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    model_id = Keyword.get(opts, :model_id, @default_model_id)

    dimension =
      Keyword.get(
        opts,
        :dimension,
        Application.get_env(:graphonomous, :embedding_dimension, @default_dimension)
      )

    task_prefixes =
      Keyword.get(
        opts,
        :task_prefixes,
        Application.get_env(:graphonomous, :embedding_task_prefixes, nil)
      )

    onnx_sequence_length =
      opts
      |> Keyword.get(
        :onnx_sequence_length,
        Application.get_env(:graphonomous, :onnx_sequence_length, @default_onnx_sequence_length)
      )
      |> normalize_onnx_sequence_length()

    requested_backend = requested_backend(opts)

    state =
      case requested_backend do
        :fallback ->
          Logger.info("Graphonomous.Embedder forced to fallback backend via config/opts")
          fallback_state(model_id, dimension, task_prefixes, onnx_sequence_length)

        _ ->
          Logger.info(
            "Graphonomous.Embedder starting async warmup model=#{model_id} dim=#{dimension}"
          )

          Process.send_after(self(), :warmup, 0)

          warming_state(model_id, dimension, task_prefixes, onnx_sequence_length)
          |> Map.put(:requested_backend, requested_backend)
      end

    {:ok, state}
  end

  defp requested_backend(opts) do
    opts
    |> Keyword.get(:backend, Application.get_env(:graphonomous, :embedder_backend, :auto))
    |> normalize_backend()
  end

  defp normalize_backend(:fallback), do: :fallback
  defp normalize_backend(:bumblebee), do: :bumblebee
  defp normalize_backend(:onnx), do: :onnx
  defp normalize_backend(:auto), do: :auto

  defp normalize_backend(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "fallback" -> :fallback
      "bumblebee" -> :bumblebee
      "onnx" -> :onnx
      "auto" -> :auto
      _ -> :auto
    end
  end

  defp normalize_backend(_), do: :auto

  defp normalize_onnx_sequence_length(value) when is_integer(value) and value > 0, do: value

  defp normalize_onnx_sequence_length(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> @default_onnx_sequence_length
    end
  end

  defp normalize_onnx_sequence_length(_), do: @default_onnx_sequence_length

  ## State constructors

  defp bumblebee_state(serving, model_id, dimension, task_prefixes, onnx_sequence_length) do
    %{
      backend: :bumblebee,
      serving: serving,
      onnx_model: nil,
      tokenizer: nil,
      model_id: model_id,
      dimension: dimension,
      warmup_in_progress: false,
      task_prefixes: task_prefixes,
      onnx_sequence_length: onnx_sequence_length
    }
  end

  defp onnx_state(
         onnx_model,
         tokenizer,
         model_id,
         dimension,
         task_prefixes,
         onnx_sequence_length
       ) do
    %{
      backend: :onnx,
      serving: nil,
      onnx_model: onnx_model,
      tokenizer: tokenizer,
      model_id: model_id,
      dimension: dimension,
      warmup_in_progress: false,
      task_prefixes: task_prefixes,
      onnx_sequence_length: onnx_sequence_length
    }
  end

  defp fallback_state(model_id, dimension, task_prefixes, onnx_sequence_length) do
    %{
      backend: :fallback,
      serving: nil,
      onnx_model: nil,
      tokenizer: nil,
      model_id: model_id,
      dimension: dimension,
      warmup_in_progress: false,
      task_prefixes: task_prefixes,
      onnx_sequence_length: onnx_sequence_length
    }
  end

  defp warming_state(model_id, dimension, task_prefixes, onnx_sequence_length) do
    %{
      backend: :warming,
      serving: nil,
      onnx_model: nil,
      tokenizer: nil,
      model_id: model_id,
      dimension: dimension,
      warmup_in_progress: true,
      task_prefixes: task_prefixes,
      onnx_sequence_length: onnx_sequence_length
    }
  end

  ## Handle calls

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, Map.take(state, [:backend, :model_id, :dimension, :onnx_sequence_length]), state}
  end

  def handle_call({:embed, text, task}, _from, state) do
    text = apply_task_prefix(text, task, state.task_prefixes)
    reply = embed_with_state(text, state)
    {:reply, reply, state}
  end

  # Backwards compat: bare {:embed, text} without task
  def handle_call({:embed, text}, _from, state) do
    reply = embed_with_state(text, state)
    {:reply, reply, state}
  end

  def handle_call({:embed_many, texts, task}, _from, state) do
    texts =
      texts
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&apply_task_prefix(&1, task, state.task_prefixes))

    result = batch_embed_with_state(texts, state)
    {:reply, result, state}
  end

  # Backwards compat
  def handle_call({:embed_many, texts}, _from, state) do
    texts = Enum.filter(texts, &is_binary/1)
    result = batch_embed_with_state(texts, state)
    {:reply, result, state}
  end

  def handle_call({:embed_many_binary, texts, task}, _from, state) do
    texts =
      texts
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&apply_task_prefix(&1, task, state.task_prefixes))

    case batch_embed_with_state(texts, state) do
      {:ok, vectors} ->
        binaries = Enum.map(vectors, &to_f32_binary/1)
        {:reply, {:ok, binaries}, state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  # Backwards compat
  def handle_call({:embed_many_binary, texts}, _from, state) do
    texts = Enum.filter(texts, &is_binary/1)

    case batch_embed_with_state(texts, state) do
      {:ok, vectors} ->
        binaries = Enum.map(vectors, &to_f32_binary/1)
        {:reply, {:ok, binaries}, state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  ## Async warmup

  @impl true
  def handle_info(:warmup, %{model_id: model_id} = state) do
    parent = self()
    requested_backend = Map.get(state, :requested_backend, :auto)

    Task.start(fn ->
      result = try_load_model(model_id, requested_backend)
      send(parent, {:warmup_complete, result})
    end)

    {:noreply, state}
  end

  def handle_info({:warmup_complete, result}, %{
        model_id: model_id,
        dimension: dimension,
        task_prefixes: task_prefixes,
        onnx_sequence_length: onnx_sequence_length
      }) do
    new_state =
      case result do
        {:ok, :bumblebee, serving} ->
          Logger.info("Graphonomous.Embedder warmup complete: Bumblebee model=#{model_id}")

          bumblebee_state(serving, model_id, dimension, task_prefixes, onnx_sequence_length)

        {:ok, :onnx, onnx_model, tokenizer} ->
          Logger.info("Graphonomous.Embedder warmup complete: ONNX model=#{model_id}")

          onnx_state(
            onnx_model,
            tokenizer,
            model_id,
            dimension,
            task_prefixes,
            onnx_sequence_length
          )

        {:error, reason} ->
          Logger.warning(
            "Graphonomous.Embedder warmup failed; using deterministic fallback: #{inspect(reason)}"
          )

          fallback_state(model_id, dimension, task_prefixes, onnx_sequence_length)
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Model loading — respects requested backend mode

  defp try_load_model(model_id, :onnx) do
    case load_onnx_model(model_id) do
      {:ok, onnx_model, tokenizer} ->
        {:ok, :onnx, onnx_model, tokenizer}

      {:error, onnx_reason} ->
        {:error, {:onnx_failed, onnx_reason}}
    end
  end

  defp try_load_model(model_id, :bumblebee) do
    case load_bumblebee_serving(model_id) do
      {:ok, serving} ->
        {:ok, :bumblebee, serving}

      {:error, bumblebee_reason} ->
        {:error, {:bumblebee_failed, bumblebee_reason}}
    end
  end

  defp try_load_model(model_id, _requested_backend) do
    case load_bumblebee_serving(model_id) do
      {:ok, serving} ->
        {:ok, :bumblebee, serving}

      {:error, bumblebee_reason} ->
        Logger.info(
          "Bumblebee failed for #{model_id}: #{inspect(bumblebee_reason)}; trying ONNX..."
        )

        case load_onnx_model(model_id) do
          {:ok, onnx_model, tokenizer} ->
            {:ok, :onnx, onnx_model, tokenizer}

          {:error, onnx_reason} ->
            {:error, {:all_backends_failed, bumblebee: bumblebee_reason, onnx: onnx_reason}}
        end
    end
  end

  ## Internal embedding dispatch

  defp batch_embed_with_state([], _state), do: {:ok, []}

  defp batch_embed_with_state(texts, %{backend: :bumblebee} = state) do
    batch_size = @default_batch_size

    results =
      texts
      |> Enum.chunk_every(batch_size)
      |> Enum.flat_map(fn chunk ->
        case run_bumblebee_batch(chunk, state.serving, state.dimension) do
          {:ok, vectors} -> Enum.map(vectors, &{:ok, &1})
          {:error, _} -> Enum.map(chunk, &{:ok, fallback_embed(&1, state.dimension)})
        end
      end)

    collect_ok(results)
  end

  defp batch_embed_with_state(texts, %{backend: :onnx, model_id: model_id} = state) do
    results =
      if onnx_force_sequential?(model_id) do
        # nomic-embed-text-v2-moe ONNX exports are unstable for batched inference
        Enum.map(texts, &embed_with_state(&1, state))
      else
        batch_size = @default_batch_size

        texts
        |> Enum.chunk_every(batch_size)
        |> Enum.flat_map(fn chunk ->
          case run_onnx_batch(chunk, state) do
            {:ok, vectors} ->
              Enum.map(vectors, &{:ok, &1})

            {:error, _} ->
              # Sequential retry path before deterministic fallback
              Enum.map(chunk, &embed_with_state(&1, state))
          end
        end)
      end

    collect_ok(results)
  end

  defp batch_embed_with_state(texts, state) do
    texts
    |> Enum.map(&embed_with_state(&1, state))
    |> collect_ok()
  end

  defp embed_with_state(text, %{backend: :bumblebee} = state) do
    case run_bumblebee(text, state.serving, state.dimension) do
      {:ok, vector} ->
        {:ok, vector}

      {:error, reason} ->
        Logger.warning(
          "Bumblebee inference failed; using deterministic fallback for this request: #{inspect(reason)}"
        )

        {:ok, fallback_embed(text, state.dimension)}
    end
  end

  defp embed_with_state(text, %{backend: :onnx} = state) do
    case run_onnx(text, state) do
      {:ok, vector} ->
        {:ok, vector}

      {:error, reason} ->
        Logger.warning(
          "ONNX inference failed; using deterministic fallback for this request: #{inspect(reason)}"
        )

        {:ok, fallback_embed(text, state.dimension)}
    end
  end

  defp embed_with_state(text, %{backend: :warming, dimension: dim}) do
    {:ok, fallback_embed(text, dim)}
  end

  defp embed_with_state(text, %{backend: :fallback, dimension: dim}) do
    {:ok, fallback_embed(text, dim)}
  end

  ## Bumblebee inference

  defp run_bumblebee(text, serving, dimension) do
    try do
      result = Nx.Serving.run(serving, text)

      result
      |> extract_embedding_tensor()
      |> tensor_to_vector()
      |> ensure_dimension(dimension)
    rescue
      e -> {:error, {:exception, e, __STACKTRACE__}}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp run_bumblebee_batch(texts, serving, dimension) when is_list(texts) do
    try do
      results = Nx.Serving.run(serving, texts)

      vectors =
        case results do
          %{embedding: tensor} ->
            unbatch_tensor(tensor, dimension)

          list when is_list(list) ->
            Enum.map(list, fn result ->
              {:ok, tensor} = extract_embedding_tensor(result)
              {:ok, vec} = tensor_to_vector({:ok, tensor})
              {:ok, normalized} = ensure_dimension({:ok, vec}, dimension)
              normalized
            end)
        end

      {:ok, vectors}
    rescue
      _ -> sequential_bumblebee_fallback(texts, serving, dimension)
    catch
      _, _ -> sequential_bumblebee_fallback(texts, serving, dimension)
    end
  end

  defp sequential_bumblebee_fallback(texts, serving, dimension) do
    results = Enum.map(texts, &run_bumblebee(&1, serving, dimension))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, v} -> v end)}
      err -> err
    end
  end

  defp unbatch_tensor(tensor, dimension) do
    n = Nx.axis_size(tensor, 0)

    for i <- 0..(n - 1) do
      vec =
        tensor
        |> Nx.slice_along_axis(i, 1, axis: 0)
        |> Nx.flatten()
        |> Nx.to_flat_list()
        |> Enum.map(&to_float/1)

      {:ok, normalized} = ensure_dimension({:ok, vec}, dimension)
      normalized
    end
  end

  defp extract_embedding_tensor(%{embedding: tensor}), do: {:ok, tensor}
  defp extract_embedding_tensor(%{"embedding" => tensor}), do: {:ok, tensor}
  defp extract_embedding_tensor(tensor), do: {:ok, tensor}

  defp tensor_to_vector({:ok, tensor}) do
    try do
      vector =
        tensor
        |> Nx.flatten()
        |> Nx.to_flat_list()
        |> Enum.map(&to_float/1)

      {:ok, vector}
    rescue
      e -> {:error, {:invalid_embedding_tensor, e}}
    end
  end

  defp ensure_dimension({:ok, vector}, dimension)
       when is_list(vector) and is_integer(dimension) do
    cond do
      length(vector) == dimension ->
        {:ok, l2_normalize(vector)}

      length(vector) > dimension ->
        vector
        |> Enum.take(dimension)
        |> l2_normalize()
        |> then(&{:ok, &1})

      true ->
        padded = vector ++ List.duplicate(0.0, dimension - length(vector))
        {:ok, l2_normalize(padded)}
    end
  end

  defp ensure_dimension({:error, _} = err, _dimension), do: err

  ## Bumblebee setup

  defp load_bumblebee_serving(model_id) do
    with {:ok, model_info} <- Bumblebee.load_model({:hf, model_id}),
         {:ok, tokenizer} <- Bumblebee.load_tokenizer({:hf, model_id}) do
      compile_opts =
        if Code.ensure_loaded?(EXLA) do
          Logger.info("Graphonomous.Embedder using EXLA backend for fast inference")
          [compiler: EXLA]
        else
          Logger.info("Graphonomous.Embedder using default Nx backend (no EXLA)")
          []
        end

      serving =
        Bumblebee.Text.TextEmbedding.text_embedding(
          model_info,
          tokenizer,
          output_pool: :mean_pooling,
          output_attribute: :hidden_state,
          embedding_processor: :l2_norm,
          compile: [batch_size: @default_batch_size, sequence_length: 512],
          defn_options: compile_opts
        )

      {:ok, serving}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_load_result, other}}
    end
  rescue
    e -> {:error, {:exception, e}}
  end

  ## ONNX backend — Ortex + HuggingFace Tokenizers

  defp load_onnx_model(model_id) do
    with {:ok, onnx_path} <- ensure_onnx_file(model_id),
         {:ok, tokenizer} <- load_hf_tokenizer(model_id) do
      Logger.info("Graphonomous.Embedder loading ONNX model from #{onnx_path}")
      onnx_model = Ortex.load(onnx_path)
      Logger.info("Graphonomous.Embedder ONNX model loaded successfully")
      {:ok, onnx_model, tokenizer}
    end
  rescue
    e -> {:error, {:onnx_load_exception, Exception.message(e)}}
  end

  defp load_hf_tokenizer(model_id) do
    Logger.info("Graphonomous.Embedder loading tokenizer for #{model_id}")
    Tokenizers.Tokenizer.from_pretrained(model_id)
  rescue
    e -> {:error, {:tokenizer_load_failed, Exception.message(e)}}
  end

  defp ensure_onnx_file(model_id) do
    # Check for explicit local path first
    case Application.get_env(:graphonomous, :onnx_model_path) do
      path when is_binary(path) and path != "" ->
        if File.exists?(path), do: {:ok, path}, else: {:error, {:onnx_file_not_found, path}}

      _ ->
        auto_download_onnx(model_id)
    end
  end

  defp auto_download_onnx(model_id) do
    cache_dir = Path.join(@onnx_cache_base, String.replace(model_id, "/", "--"))
    onnx_path = Path.join(cache_dir, "model.onnx")

    if File.exists?(onnx_path) do
      {:ok, onnx_path}
    else
      File.mkdir_p!(cache_dir)
      download_onnx_from_hf(model_id, onnx_path)
    end
  end

  defp download_onnx_from_hf(model_id, target_path) do
    url = ~c"https://huggingface.co/#{model_id}/resolve/main/onnx/model.onnx"
    Logger.info("Graphonomous.Embedder downloading ONNX model from HuggingFace: #{model_id}")

    :ssl.start()
    :inets.start()

    http_opts = [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ],
      # Follow redirects (HuggingFace uses CDN redirects for large files)
      autoredirect: true,
      timeout: 600_000,
      connect_timeout: 30_000
    ]

    case :httpc.request(:get, {url, []}, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        File.write!(target_path, body)
        size_mb = Float.round(byte_size(body) / 1_048_576, 1)
        Logger.info("Graphonomous.Embedder ONNX model downloaded: #{size_mb}MB → #{target_path}")
        {:ok, target_path}

      {:ok, {{_, 404, _}, _headers, _body}} ->
        Logger.warning("""
        ONNX model not found on HuggingFace for #{model_id}.
        If this model requires a local ONNX export, run:
          python scripts/export_onnx_v2_moe.py
        Then retry — the file will be found at #{target_path}
        """)

        {:error, {:onnx_not_published, model_id}}

      {:ok, {{_, status, reason}, _headers, _body}} ->
        {:error, {:onnx_download_failed, status, to_string(reason)}}

      {:error, reason} ->
        {:error, {:onnx_download_failed, reason}}
    end
  end

  ## ONNX inference

  defp run_onnx(text, %{
         onnx_model: model,
         tokenizer: tokenizer,
         dimension: dimension,
         onnx_sequence_length: onnx_sequence_length
       }) do
    try do
      {:ok, encoding} = Tokenizers.Tokenizer.encode(tokenizer, text)

      {input_ids, attention_mask} = fixed_length_onnx_inputs(encoding, onnx_sequence_length)

      input_ids_t = Nx.tensor([input_ids], type: :s64)
      attention_mask_t = Nx.tensor([attention_mask], type: :s64)
      token_type_ids_t = Nx.broadcast(Nx.tensor(0, type: :s64), Nx.shape(input_ids_t))

      # Run ONNX model — input order: input_ids, token_type_ids, attention_mask
      output_tuple = Ortex.run(model, {input_ids_t, token_type_ids_t, attention_mask_t})

      # First output is usually last_hidden_state {1, seq_len, hidden_dim}
      hidden_state = elem(output_tuple, 0) |> Nx.backend_transfer()

      vector = mean_pool(hidden_state, attention_mask_t, dimension)
      {:ok, l2_normalize(vector)}
    rescue
      e -> {:error, {:onnx_inference_error, Exception.message(e)}}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp run_onnx_batch(texts, %{
         onnx_model: model,
         tokenizer: tokenizer,
         dimension: dimension,
         onnx_sequence_length: onnx_sequence_length
       }) do
    try do
      encodings =
        Enum.map(texts, fn text ->
          {:ok, enc} = Tokenizers.Tokenizer.encode(tokenizer, text)
          enc
        end)

      {ids_list, mask_list} =
        Enum.reduce(encodings, {[], []}, fn enc, {ids_acc, mask_acc} ->
          {ids, mask} = fixed_length_onnx_inputs(enc, onnx_sequence_length)
          {ids_acc ++ [ids], mask_acc ++ [mask]}
        end)

      input_ids_t = Nx.tensor(ids_list, type: :s64)
      attention_mask_t = Nx.tensor(mask_list, type: :s64)
      token_type_ids_t = Nx.broadcast(Nx.tensor(0, type: :s64), Nx.shape(input_ids_t))

      # Input order: input_ids, token_type_ids, attention_mask
      output_tuple = Ortex.run(model, {input_ids_t, token_type_ids_t, attention_mask_t})
      hidden_state = elem(output_tuple, 0) |> Nx.backend_transfer()

      batch_size = length(texts)

      vectors =
        for i <- 0..(batch_size - 1) do
          row_hidden = Nx.slice_along_axis(hidden_state, i, 1, axis: 0)
          row_mask = Nx.slice_along_axis(attention_mask_t, i, 1, axis: 0)
          vec = mean_pool(row_hidden, row_mask, dimension)
          l2_normalize(vec)
        end

      {:ok, vectors}
    rescue
      e -> {:error, {:onnx_batch_error, Exception.message(e)}}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp mean_pool(hidden_state, attention_mask, dimension) do
    # hidden_state: {1, seq_len, hidden_dim}, attention_mask: {1, seq_len}
    mask_expanded =
      attention_mask
      |> Nx.new_axis(-1)
      |> Nx.as_type(:f32)

    hidden_f32 = Nx.as_type(hidden_state, :f32)
    masked = Nx.multiply(hidden_f32, mask_expanded)
    summed = Nx.sum(masked, axes: [1])
    count = Nx.sum(mask_expanded, axes: [1])
    pooled = Nx.divide(summed, Nx.max(count, Nx.tensor(1.0e-9)))

    pooled
    |> Nx.squeeze()
    |> Nx.to_flat_list()
    |> Enum.map(&to_float/1)
    |> ensure_dimension_list(dimension)
  end

  defp ensure_dimension_list(vector, dimension) do
    cond do
      length(vector) == dimension -> vector
      length(vector) > dimension -> Enum.take(vector, dimension)
      true -> vector ++ List.duplicate(0.0, dimension - length(vector))
    end
  end

  # nomic-v2-moe ONNX now uses a dense-forward export (all experts computed for
  # all tokens with static shapes). Works in Ortex 0.1.10 (ORT 1.19 via ort 2.0.0-rc.8).
  # The original sparse MoE export used Expand/ScatterElements with data-dependent
  # shapes which failed in every ORT version. Re-exported with dense computation
  # that produces identical embeddings (cosine sim 1.0 vs original).
  defp unstable_onnx_model?(_model_id), do: false

  defp onnx_force_sequential?(_model_id), do: false

  defp fixed_length_onnx_inputs(encoding, seq_len) do
    input_ids =
      encoding
      |> Tokenizers.Encoding.get_ids()
      |> Enum.take(seq_len)
      |> pad_to_length(seq_len, 0)

    attention_mask =
      encoding
      |> Tokenizers.Encoding.get_attention_mask()
      |> Enum.take(seq_len)
      |> pad_to_length(seq_len, 0)

    {input_ids, attention_mask}
  end

  defp pad_to_length(list, length, pad_value) do
    case length - Kernel.length(list) do
      diff when diff > 0 -> list ++ List.duplicate(pad_value, diff)
      _ -> list
    end
  end

  ## Deterministic fallback embedder

  defp fallback_embed(text, dimension)
       when is_binary(text) and is_integer(dimension) and dimension > 0 do
    text = String.trim(text)

    tokens =
      text
      |> String.downcase()
      |> String.split(~r/[^[:alnum:]]+/u, trim: true)

    tokens =
      if tokens == [] do
        if text == "", do: ["_empty_"], else: [text]
      else
        tokens
      end

    weighted_buckets =
      tokens
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {token, idx}, acc ->
        acc
        |> add_token_feature(token, idx, dimension, 1.0)
        |> add_trigrams(token, idx, dimension, 0.5)
      end)

    vector =
      for i <- 0..(dimension - 1) do
        Map.get(weighted_buckets, i, 0.0)
      end

    l2_normalize(vector)
  end

  defp add_token_feature(acc, token, idx, dimension, scale) do
    bucket = :erlang.phash2({"tok", token}, dimension)
    sign = if rem(:erlang.phash2({"sgn", token}, 2), 2) == 0, do: 1.0, else: -1.0
    order_bias = 1.0 / (1.0 + idx)
    token_weight = 1.0 + :math.log(1 + byte_size(token))
    delta = sign * token_weight * order_bias * scale
    Map.update(acc, bucket, delta, &(&1 + delta))
  end

  defp add_trigrams(acc, token, idx, dimension, scale) do
    token
    |> trigrams()
    |> Enum.reduce(acc, fn trigram, inner ->
      add_token_feature(inner, "tri:" <> trigram, idx, dimension, scale)
    end)
  end

  defp trigrams(token) when byte_size(token) < 3, do: [token]

  defp trigrams(token) do
    chars = String.graphemes(token)
    max_i = length(chars) - 3

    for i <- 0..max_i do
      chars
      |> Enum.slice(i, 3)
      |> Enum.join()
    end
  end

  ## Task prefix support

  defp apply_task_prefix(text, nil, _prefixes), do: text
  defp apply_task_prefix(text, _task, nil), do: text

  defp apply_task_prefix(text, task, prefixes) when is_map(prefixes) do
    case Map.get(prefixes, task) do
      nil -> text
      prefix when is_binary(prefix) -> prefix <> text
    end
  end

  defp apply_task_prefix(text, _task, _prefixes), do: text

  ## Helpers

  defp collect_ok(results) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        vectors = Enum.map(results, fn {:ok, vector} -> vector end)
        {:ok, vectors}

      {:error, _} = err ->
        err
    end
  end

  defp l2_normalize(vector) do
    norm =
      vector
      |> Enum.reduce(0.0, fn x, acc -> acc + x * x end)
      |> :math.sqrt()

    if norm <= 1.0e-12 do
      vector
    else
      Enum.map(vector, &(&1 / norm))
    end
  end

  defp to_f32_binary(vector) when is_list(vector) do
    Enum.reduce(vector, <<>>, fn v, acc -> <<acc::binary, to_float(v)::float-little-32>> end)
  end

  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_binary(v), do: v |> Float.parse() |> elem_or_zero()
  defp to_float(_), do: 0.0

  defp elem_or_zero({f, _rest}), do: f
  defp elem_or_zero(:error), do: 0.0
end
