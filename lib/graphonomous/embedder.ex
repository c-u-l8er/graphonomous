defmodule Graphonomous.Embedder do
  @moduledoc """
  Embedding runtime for Graphonomous.

  Primary mode:
  - Uses Bumblebee + Nx.Serving with `sentence-transformers/all-MiniLM-L6-v2`
    (384 dimensions).

  Fallback mode:
  - If model loading or inference is unavailable, uses a deterministic local
    hashing embedder (also 384 dimensions by default), so the rest of the system
    can keep working.
  """

  use GenServer

  require Logger

  @default_model_id "sentence-transformers/all-MiniLM-L6-v2"
  @default_dimension 384
  @default_timeout 15_000
  @default_batch_size 8

  @type backend :: :bumblebee | :fallback | :warming
  @type embedding :: [float()]

  @type state :: %{
          backend: backend(),
          serving: term() | nil,
          model_id: String.t(),
          dimension: pos_integer(),
          warmup_in_progress: boolean()
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns an embedding vector for a single text input.
  """
  @spec embed(String.t(), keyword()) :: {:ok, embedding()} | {:error, term()}
  def embed(text, opts \\ []) when is_binary(text) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(__MODULE__, {:embed, text}, timeout)
  end

  @doc """
  Returns embeddings for multiple text inputs.
  """
  @spec embed_many([String.t()], keyword()) :: {:ok, [embedding()]} | {:error, term()}
  def embed_many(texts, opts \\ []) when is_list(texts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(__MODULE__, {:embed_many, texts}, timeout)
  end

  @doc """
  Returns a little-endian float32 binary embedding suitable for SQLite BLOB storage.
  """
  @spec embed_binary(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def embed_binary(text, opts \\ []) when is_binary(text) do
    with {:ok, vector} <- embed(text, opts) do
      {:ok, to_f32_binary(vector)}
    end
  end

  @doc """
  Returns little-endian float32 binary embeddings for multiple texts.
  Uses true batch inference when the Bumblebee backend is active.
  """
  @spec embed_many_binary([String.t()], keyword()) :: {:ok, [binary()]} | {:error, term()}
  def embed_many_binary(texts, opts \\ []) when is_list(texts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout * length(texts))
    GenServer.call(__MODULE__, {:embed_many_binary, texts}, timeout)
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
    dimension = Keyword.get(opts, :dimension, @default_dimension)
    requested_backend = requested_backend(opts)

    state =
      case requested_backend do
        :fallback ->
          Logger.info("Graphonomous.Embedder forced to fallback backend via config/opts")
          fallback_state(model_id, dimension)

        _ ->
          Logger.info("Graphonomous.Embedder starting async Bumblebee warmup model=#{model_id}")
          Process.send_after(self(), :warmup_bumblebee, 0)
          warming_state(model_id, dimension)
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
  defp normalize_backend(:auto), do: :auto

  defp normalize_backend(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "fallback" -> :fallback
      "bumblebee" -> :bumblebee
      "auto" -> :auto
      _ -> :auto
    end
  end

  defp normalize_backend(_), do: :auto

  defp bumblebee_state(serving, model_id, dimension) do
    %{
      backend: :bumblebee,
      serving: serving,
      model_id: model_id,
      dimension: dimension,
      warmup_in_progress: false
    }
  end

  defp fallback_state(model_id, dimension) do
    %{
      backend: :fallback,
      serving: nil,
      model_id: model_id,
      dimension: dimension,
      warmup_in_progress: false
    }
  end

  defp warming_state(model_id, dimension) do
    %{
      backend: :warming,
      serving: nil,
      model_id: model_id,
      dimension: dimension,
      warmup_in_progress: true
    }
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, Map.take(state, [:backend, :model_id, :dimension]), state}
  end

  def handle_call({:embed, text}, _from, state) do
    reply = embed_with_state(text, state)
    {:reply, reply, state}
  end

  def handle_call({:embed_many, texts}, _from, state) do
    texts = Enum.filter(texts, &is_binary/1)
    result = batch_embed_with_state(texts, state)
    {:reply, result, state}
  end

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

  @impl true
  def handle_info(:warmup_bumblebee, %{model_id: model_id} = state) do
    parent = self()

    Task.start(fn ->
      result = load_bumblebee_serving(model_id)
      send(parent, {:warmup_bumblebee_complete, result})
    end)

    {:noreply, state}
  end

  def handle_info({:warmup_bumblebee_complete, result}, %{
        model_id: model_id,
        dimension: dimension
      }) do
    new_state =
      case result do
        {:ok, serving} ->
          Logger.info("Graphonomous.Embedder warmup complete with Bumblebee model=#{model_id}")
          bumblebee_state(serving, model_id, dimension)

        {:error, reason} ->
          Logger.warning(
            "Graphonomous.Embedder warmup failed; using deterministic fallback: #{inspect(reason)}"
          )

          fallback_state(model_id, dimension)
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal embedding

  defp batch_embed_with_state([], _state), do: {:ok, []}

  defp batch_embed_with_state(texts, %{backend: :bumblebee} = state) do
    # Process in chunks matching the serving batch_size for true GPU batching
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
        # graceful degradation for runtime failures (e.g. model process crash)
        Logger.warning(
          "Bumblebee inference failed; using deterministic fallback for this request: #{inspect(reason)}"
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
      # Bumblebee's Nx.Serving accepts a list of strings for batched inference.
      # With batch_size > 1, the serving processes multiple texts in one GPU pass.
      results = Nx.Serving.run(serving, texts)

      vectors =
        case results do
          %{embedding: tensor} ->
            # Batched result — tensor shape is {n, dim}
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
      _ ->
        # Fall back to sequential processing on batch failure
        sequential_fallback(texts, serving, dimension)
    catch
      _, _ ->
        sequential_fallback(texts, serving, dimension)
    end
  end

  defp sequential_fallback(texts, serving, dimension) do
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
      # Use EXLA compiler when available for fast inference (CPU or GPU).
      # Falls back to default Nx backend (BinaryBackend) if EXLA is not loaded.
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
        # main token feature
        acc
        |> add_token_feature(token, idx, dimension, 1.0)
        # character-trigram feature for slight semantic stability
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
