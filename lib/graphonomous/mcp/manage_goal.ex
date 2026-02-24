defmodule Graphonomous.MCP.ManageGoal do
  @moduledoc """
  MCP tool for GoalGraph CRUD, lifecycle transitions, and related goal operations.

  Supported operations:

    - `create_goal`
    - `get_goal`
    - `list_goals`
    - `update_goal`
    - `delete_goal`
    - `transition_goal`
    - `set_progress`
    - `link_nodes`
    - `unlink_nodes`
    - `review_goal`
  """

  use Anubis.Server.Component, type: :tool

  @valid_operations ~w(
    create_goal
    get_goal
    list_goals
    update_goal
    delete_goal
    transition_goal
    set_progress
    link_nodes
    unlink_nodes
    review_goal
  )

  schema do
    field(:operation, :string,
      required: true,
      description:
        "Goal operation: create_goal|get_goal|list_goals|update_goal|delete_goal|transition_goal|set_progress|link_nodes|unlink_nodes|review_goal"
    )

    field(:goal_id, :string,
      description:
        "Goal ID (required for get/update/delete/transition/set_progress/link_nodes/unlink_nodes/review_goal)"
    )

    field(:payload, :string,
      description:
        "JSON object for create/update/list filters. Example: {\"title\":\"Ship v0.1\",\"priority\":\"high\"}"
    )

    field(:status, :string, description: "Target status for transition_goal")

    field(:progress, :number, description: "Progress value in [0.0, 1.0] for set_progress")

    field(:node_ids, :string, description: "JSON array of node IDs for link_nodes/unlink_nodes")

    field(:metadata, :string, description: "JSON object metadata for transition_goal")

    field(:signal, :string,
      description: "JSON object signal for review_goal (coverage evaluation input)"
    )

    field(:opts, :string, description: "JSON object options for review_goal coverage evaluation")
  end

  @impl true
  def execute(params, frame) do
    with {:ok, operation} <- read_operation(params),
         {:ok, result} <- dispatch(operation, params) do
      response = %{
        status: "ok",
        operation: operation,
        result: serialize(result)
      }

      {:ok, Jason.encode!(response), frame}
    else
      {:error, reason} ->
        response = %{
          status: "error",
          error: format_error(reason)
        }

        {:ok, Jason.encode!(response), frame}
    end
  end

  # -- Dispatch ----------------------------------------------------------------

  defp dispatch("create_goal", params) do
    attrs = payload_map(params)

    with {:ok, attrs} <- ensure_title(attrs) do
      Graphonomous.create_goal(attrs)
      |> normalize_result()
    end
  end

  defp dispatch("get_goal", params) do
    with {:ok, goal_id} <- read_required_string(params, :goal_id) do
      Graphonomous.get_goal(goal_id)
      |> normalize_result()
    end
  end

  defp dispatch("list_goals", params) do
    filters = payload_map(params)

    Graphonomous.list_goals(filters)
    |> normalize_result()
  end

  defp dispatch("update_goal", params) do
    with {:ok, goal_id} <- read_required_string(params, :goal_id),
         attrs <- payload_map(params) do
      Graphonomous.update_goal(goal_id, attrs)
      |> normalize_result()
    end
  end

  defp dispatch("delete_goal", params) do
    with {:ok, goal_id} <- read_required_string(params, :goal_id) do
      Graphonomous.delete_goal(goal_id)
      |> normalize_result()
    end
  end

  defp dispatch("transition_goal", params) do
    with {:ok, goal_id} <- read_required_string(params, :goal_id),
         {:ok, status} <- read_required_string(params, :status),
         metadata <- decode_json_map(fetch(params, :metadata), %{}) do
      Graphonomous.transition_goal(goal_id, status, metadata)
      |> normalize_result()
    end
  end

  defp dispatch("set_progress", params) do
    with {:ok, goal_id} <- read_required_string(params, :goal_id),
         {:ok, progress} <- read_progress(params) do
      Graphonomous.set_goal_progress(goal_id, progress)
      |> normalize_result()
    end
  end

  defp dispatch("link_nodes", params) do
    with {:ok, goal_id} <- read_required_string(params, :goal_id),
         {:ok, node_ids} <- read_node_ids(params) do
      Graphonomous.link_goal_nodes(goal_id, node_ids)
      |> normalize_result()
    end
  end

  defp dispatch("unlink_nodes", params) do
    with {:ok, goal_id} <- read_required_string(params, :goal_id),
         {:ok, node_ids} <- read_node_ids(params) do
      Graphonomous.unlink_goal_nodes(goal_id, node_ids)
      |> normalize_result()
    end
  end

  defp dispatch("review_goal", params) do
    with {:ok, goal_id} <- read_required_string(params, :goal_id),
         {:ok, signal} <- read_signal(params),
         opts_map <- decode_json_map(fetch(params, :opts), %{}),
         opts <- map_to_keyword(opts_map) do
      case Graphonomous.review_goal(goal_id, signal, opts) do
        {:ok, goal, evaluation} ->
          {:ok, %{goal: goal, evaluation: evaluation}}

        {goal, evaluation} when is_map(goal) and is_map(evaluation) ->
          {:ok, %{goal: goal, evaluation: evaluation}}

        {:error, _} = err ->
          err

        other ->
          {:error, {:unexpected_review_result, other}}
      end
    end
  end

  # -- Read/parse helpers ------------------------------------------------------

  defp read_operation(params) do
    operation =
      params
      |> fetch(:operation)
      |> to_optional_string()
      |> normalize_operation()

    cond do
      is_nil(operation) ->
        {:error, {:missing_param, :operation}}

      operation in @valid_operations ->
        {:ok, operation}

      true ->
        {:error, {:invalid_operation, operation}}
    end
  end

  defp read_required_string(params, key) do
    case fetch(params, key) |> to_optional_string() do
      nil -> {:error, {:missing_param, key}}
      value -> {:ok, value}
    end
  end

  defp read_progress(params) do
    value = fetch(params, :progress)

    cond do
      is_float(value) ->
        {:ok, clamp01(value)}

      is_integer(value) ->
        {:ok, clamp01(value * 1.0)}

      is_binary(value) ->
        case Float.parse(String.trim(value)) do
          {f, _} -> {:ok, clamp01(f)}
          :error -> {:error, {:invalid_param, :progress}}
        end

      true ->
        {:error, {:invalid_param, :progress}}
    end
  end

  defp read_node_ids(params) do
    # Prefer explicit node_ids field; fallback to payload.node_ids
    raw = fetch(params, :node_ids)

    cond do
      is_binary(raw) ->
        decode_json_string_array(raw)

      is_list(raw) ->
        {:ok, normalize_string_list(raw)}

      true ->
        payload = payload_map(params)

        case Map.get(payload, "node_ids") || Map.get(payload, :node_ids) do
          list when is_list(list) -> {:ok, normalize_string_list(list)}
          value when is_binary(value) -> decode_json_string_array(value)
          _ -> {:error, {:missing_param, :node_ids}}
        end
    end
  end

  defp read_signal(params) do
    case fetch(params, :signal) do
      nil ->
        payload = payload_map(params)

        case Map.get(payload, "signal") || Map.get(payload, :signal) do
          signal when is_map(signal) -> {:ok, signal}
          _ -> {:error, {:missing_param, :signal}}
        end

      value when is_map(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          _ -> {:error, {:invalid_param, :signal}}
        end

      _ ->
        {:error, {:invalid_param, :signal}}
    end
  end

  defp payload_map(params) do
    decode_json_map(fetch(params, :payload), %{})
  end

  defp ensure_title(attrs) when is_map(attrs) do
    title =
      Map.get(attrs, "title") ||
        Map.get(attrs, :title)

    if is_binary(title) and String.trim(title) != "" do
      {:ok, attrs}
    else
      {:error, {:missing_param, :title}}
    end
  end

  # -- Normalization -----------------------------------------------------------

  defp normalize_operation(nil), do: nil

  defp normalize_operation(operation) when is_binary(operation) do
    operation
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_operation(operation), do: operation |> to_string() |> normalize_operation()

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(&to_optional_string/1)
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_string_list(_), do: []

  defp clamp01(v) when v < 0.0, do: 0.0
  defp clamp01(v) when v > 1.0, do: 1.0
  defp clamp01(v), do: v

  defp to_optional_string(nil), do: nil

  defp to_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp to_optional_string(value), do: value |> to_string() |> to_optional_string()

  # -- Decoding ----------------------------------------------------------------

  defp decode_json_map(nil, default), do: default
  defp decode_json_map(value, _default) when is_map(value), do: value

  defp decode_json_map(value, default) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> default
    end
  end

  defp decode_json_map(_value, default), do: default

  defp decode_json_string_array(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) ->
        {:ok, normalize_string_list(decoded)}

      _ ->
        {:error, {:invalid_param, :node_ids}}
    end
  end

  defp map_to_keyword(map) when is_map(map) do
    Enum.reduce(map, [], fn {k, v}, acc ->
      key =
        cond do
          is_atom(k) -> k
          is_binary(k) -> String.to_atom(k)
          true -> nil
        end

      if is_atom(key), do: [{key, v} | acc], else: acc
    end)
    |> Enum.reverse()
  end

  # -- Result shaping ----------------------------------------------------------

  defp normalize_result({:error, _} = err), do: err
  defp normalize_result(other), do: {:ok, other}

  defp serialize(value) when is_list(value), do: Enum.map(value, &serialize/1)

  defp serialize(value) when is_map(value) do
    value
    |> maybe_from_struct()
    |> Enum.into(%{}, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k

      serialized =
        case v do
          %DateTime{} = dt -> DateTime.to_iso8601(dt)
          _ -> serialize(v)
        end

      {key, serialized}
    end)
  end

  defp serialize(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&serialize/1)
  end

  defp serialize(value), do: value

  defp maybe_from_struct(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp maybe_from_struct(map), do: map

  # -- Param access + errors ---------------------------------------------------

  defp fetch(params, key) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end

  defp format_error({:missing_param, key}), do: "#{key} is required"
  defp format_error({:invalid_param, key}), do: "#{key} is invalid"

  defp format_error({:invalid_operation, operation}) do
    "operation '#{operation}' is invalid. Allowed: #{Enum.join(@valid_operations, ", ")}"
  end

  defp format_error(reason), do: inspect(reason)
end
