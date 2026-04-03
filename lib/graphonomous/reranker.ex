defmodule Graphonomous.Reranker do
  @moduledoc """
  Cross-encoder reranker for two-stage retrieval.

  Uses a cross-encoder model (e.g. ms-marco-MiniLM-L-6-v2) via ONNX/Ortex
  to rescore query-document pairs. Cross-encoders jointly attend to query+document
  and produce much better relevance scores than bi-encoder cosine similarity,
  at the cost of O(n) model calls per query.

  Usage:
    - After initial ANN+BM25 retrieval, take top-k candidates
    - Rerank with cross-encoder to get final ordering
    - Only applies when the ONNX model is loaded; falls back to identity otherwise

  Default model: cross-encoder/ms-marco-MiniLM-L-6-v2 (23MB ONNX)
  """

  use GenServer

  require Logger

  @default_model_id "cross-encoder/ms-marco-MiniLM-L-6-v2"
  @onnx_cache_base Path.join([System.user_home() || "/tmp", ".cache", "graphonomous", "onnx"])

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Rerank a list of `{node_id, content}` pairs by cross-encoder relevance to query.
  Returns `{:ok, [{node_id, rerank_score}]}` sorted by descending relevance.

  Falls back to the original order if the model isn't loaded.
  """
  @spec rerank(String.t(), [{String.t(), String.t()}], keyword()) ::
          {:ok, [{String.t(), float()}]}
  def rerank(query, candidates, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(__MODULE__, {:rerank, query, candidates}, timeout)
  end

  @doc """
  Runtime info.
  """
  @spec info() :: map()
  def info do
    GenServer.call(__MODULE__, :info)
  end

  ## GenServer

  @impl true
  def init(opts) do
    model_id = Keyword.get(opts, :model_id, @default_model_id)

    enabled =
      Keyword.get(opts, :enabled, Application.get_env(:graphonomous, :reranker_enabled, true))

    if enabled do
      Process.send_after(self(), :warmup, 1_000)
      {:ok, %{model: nil, tokenizer: nil, model_id: model_id, status: :warming}}
    else
      Logger.info("Reranker disabled via config")
      {:ok, %{model: nil, tokenizer: nil, model_id: model_id, status: :disabled}}
    end
  end

  @impl true
  def handle_call({:rerank, query, candidates}, _from, %{status: :ready} = state) do
    result = do_rerank(query, candidates, state)
    {:reply, result, state}
  end

  def handle_call({:rerank, _query, candidates}, _from, state) do
    # Not ready — return candidates in original order with placeholder scores
    fallback =
      candidates
      |> Enum.with_index()
      |> Enum.map(fn {{node_id, _content}, idx} ->
        {node_id, 1.0 / (idx + 1)}
      end)

    {:reply, {:ok, fallback}, state}
  end

  def handle_call(:info, _from, state) do
    {:reply, %{status: state.status, model_id: state.model_id}, state}
  end

  @impl true
  def handle_info(:warmup, state) do
    parent = self()

    Task.start(fn ->
      result = load_cross_encoder(state.model_id)
      send(parent, {:warmup_complete, result})
    end)

    {:noreply, state}
  end

  def handle_info({:warmup_complete, {:ok, model, tokenizer}}, state) do
    Logger.info("Reranker warmup complete: #{state.model_id}")
    {:noreply, %{state | model: model, tokenizer: tokenizer, status: :ready}}
  end

  def handle_info({:warmup_complete, {:error, reason}}, state) do
    Logger.warning("Reranker warmup failed: #{inspect(reason)}")
    {:noreply, %{state | status: :failed}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Cross-encoder inference

  defp do_rerank(query, candidates, %{model: model, tokenizer: tokenizer}) do
    scored =
      Enum.map(candidates, fn {node_id, content} ->
        score = cross_encode_score(query, content, model, tokenizer)
        {node_id, score}
      end)

    sorted = Enum.sort_by(scored, fn {_id, score} -> score end, :desc)
    {:ok, sorted}
  rescue
    e ->
      Logger.warning("Reranker inference error: #{Exception.message(e)}")
      # Fallback to original order
      fallback =
        candidates
        |> Enum.with_index()
        |> Enum.map(fn {{node_id, _}, idx} -> {node_id, 1.0 / (idx + 1)} end)

      {:ok, fallback}
  end

  defp cross_encode_score(query, document, model, tokenizer) do
    # Cross-encoders take a sentence pair as input
    {:ok, encoding} = Tokenizers.Tokenizer.encode(tokenizer, {query, document})
    input_ids = Tokenizers.Encoding.get_ids(encoding)
    attention_mask = Tokenizers.Encoding.get_attention_mask(encoding)

    # Truncate to max 512 tokens
    max_len = 512
    input_ids = Enum.take(input_ids, max_len)
    attention_mask = Enum.take(attention_mask, max_len)

    input_ids_t = Nx.tensor([input_ids], type: :s64)
    attention_mask_t = Nx.tensor([attention_mask], type: :s64)
    token_type_ids_t = build_token_type_ids(encoding, max_len)

    output_tuple = Ortex.run(model, {input_ids_t, attention_mask_t, token_type_ids_t})

    # Cross-encoder output is logits {1, 1} — single relevance score
    logits = elem(output_tuple, 0) |> Nx.backend_transfer()

    logits
    |> Nx.squeeze()
    |> Nx.to_number()
    |> sigmoid()
  rescue
    _ -> 0.0
  end

  defp build_token_type_ids(encoding, max_len) do
    type_ids = Tokenizers.Encoding.get_type_ids(encoding)
    type_ids = Enum.take(type_ids, max_len)
    Nx.tensor([type_ids], type: :s64)
  end

  defp sigmoid(x) do
    1.0 / (1.0 + :math.exp(-x))
  end

  ## Model loading

  defp load_cross_encoder(model_id) do
    with {:ok, onnx_path} <- ensure_onnx_file(model_id),
         {:ok, tokenizer} <- load_tokenizer(model_id) do
      Logger.info("Reranker loading ONNX model from #{onnx_path}")
      model = Ortex.load(onnx_path)
      Logger.info("Reranker ONNX cross-encoder loaded")
      {:ok, model, tokenizer}
    end
  rescue
    e -> {:error, {:load_exception, Exception.message(e)}}
  end

  defp load_tokenizer(model_id) do
    Tokenizers.Tokenizer.from_pretrained(model_id)
  rescue
    e -> {:error, {:tokenizer_failed, Exception.message(e)}}
  end

  defp ensure_onnx_file(model_id) do
    cache_dir = Path.join(@onnx_cache_base, String.replace(model_id, "/", "--"))
    onnx_path = Path.join(cache_dir, "model.onnx")

    if File.exists?(onnx_path) do
      {:ok, onnx_path}
    else
      File.mkdir_p!(cache_dir)
      download_onnx(model_id, onnx_path)
    end
  end

  defp download_onnx(model_id, target_path) do
    url = ~c"https://huggingface.co/#{model_id}/resolve/main/onnx/model.onnx"
    Logger.info("Reranker downloading ONNX model: #{model_id}")

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
      autoredirect: true,
      timeout: 300_000,
      connect_timeout: 30_000
    ]

    case :httpc.request(:get, {url, []}, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        File.write!(target_path, body)
        size_mb = Float.round(byte_size(body) / 1_048_576, 1)
        Logger.info("Reranker ONNX model downloaded: #{size_mb}MB → #{target_path}")
        {:ok, target_path}

      {:ok, {{_, status, reason}, _, _}} ->
        {:error, {:download_failed, status, to_string(reason)}}

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end
end
