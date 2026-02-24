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

  @type backend :: :bumblebee | :fallback
  @type embedding :: [float()]

  @type state :: %{
          backend: backend(),
          serving: term() | nil,
          model_id: String.t(),
          dimension: pos_integer()
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
          case load_bumblebee_serving(model_id) do
            {:ok, serving} ->
              Logger.info("Graphonomous.Embedder started with Bumblebee model=#{model_id}")
              bumblebee_state(serving, model_id, dimension)

            {:error, reason} ->
              Logger.warning(
                "Graphonomous.Embedder falling back to deterministic embedder: #{inspect(reason)}"
              )

              fallback_state(model_id, dimension)
          end
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
      dimension: dimension
    }
  end

  defp fallback_state(model_id, dimension) do
    %{
      backend: :fallback,
      serving: nil,
      model_id: model_id,
      dimension: dimension
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

    result =
      texts
      |> Enum.map(&embed_with_state(&1, state))
      |> collect_ok()

    {:reply, result, state}
  end

  ## Internal embedding

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
      serving =
        Bumblebee.Text.TextEmbedding.text_embedding(
          model_info,
          tokenizer,
          output_pool: :mean_pooling,
          output_attribute: :hidden_state,
          embedding_processor: :l2_norm
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
