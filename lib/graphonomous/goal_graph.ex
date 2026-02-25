defmodule Graphonomous.GoalGraph do
  @moduledoc """
  Durable GoalGraph orchestrator.

  This module is the policy and orchestration layer over `Graphonomous.Store` for
  durable goal persistence. It centralizes:

  - goal lifecycle validation
  - status transition rules
  - dependency and linkage management
  - progress updates and completion semantics
  - optional epistemic coverage annotations for goals

  Persistence is delegated to `Graphonomous.Store` (`insert_goal/get_goal/list_goals/update_goal/delete_goal`).
  """

  use GenServer

  alias Graphonomous.{Coverage, Store}
  alias Graphonomous.Types.Goal

  @type goal_status :: :proposed | :active | :blocked | :completed | :abandoned
  @type state :: %{started_at: DateTime.t()}

  @valid_statuses [:proposed, :active, :blocked, :completed, :abandoned]
  @valid_timescales [:immediate, :short_term, :medium_term, :long_term]
  @valid_sources [:user, :system, :inferred, :policy]
  @valid_priorities [:low, :normal, :high, :critical]
  @review_goal_timeout_ms 30_000

  @transitions %{
    proposed: [:active, :blocked, :abandoned],
    active: [:blocked, :completed, :abandoned],
    blocked: [:active, :abandoned, :proposed],
    completed: [],
    abandoned: [:proposed, :active]
  }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec create_goal(map()) :: {:ok, Goal.t()} | {:error, term()}
  def create_goal(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:create_goal, attrs})
  end

  @spec get_goal(binary()) :: {:ok, Goal.t()} | {:error, :not_found}
  def get_goal(goal_id) when is_binary(goal_id) do
    GenServer.call(__MODULE__, {:get_goal, goal_id})
  end

  @spec list_goals(map()) :: {:ok, [Goal.t()]}
  def list_goals(filters \\ %{}) when is_map(filters) do
    GenServer.call(__MODULE__, {:list_goals, filters})
  end

  @spec update_goal(binary(), map()) :: {:ok, Goal.t()} | {:error, term()}
  def update_goal(goal_id, attrs) when is_binary(goal_id) and is_map(attrs) do
    GenServer.call(__MODULE__, {:update_goal, goal_id, attrs})
  end

  @spec delete_goal(binary()) :: :ok | {:error, :not_found}
  def delete_goal(goal_id) when is_binary(goal_id) do
    GenServer.call(__MODULE__, {:delete_goal, goal_id})
  end

  @spec transition_goal(binary(), goal_status() | binary(), map()) ::
          {:ok, Goal.t()} | {:error, term()}
  def transition_goal(goal_id, to_status, metadata \\ %{})
      when is_binary(goal_id) and is_map(metadata) do
    GenServer.call(__MODULE__, {:transition_goal, goal_id, to_status, metadata})
  end

  @spec add_dependency(binary(), binary()) :: {:ok, Goal.t()} | {:error, term()}
  def add_dependency(goal_id, dependency_goal_id)
      when is_binary(goal_id) and is_binary(dependency_goal_id) do
    GenServer.call(__MODULE__, {:add_dependency, goal_id, dependency_goal_id})
  end

  @spec remove_dependency(binary(), binary()) :: {:ok, Goal.t()} | {:error, term()}
  def remove_dependency(goal_id, dependency_goal_id)
      when is_binary(goal_id) and is_binary(dependency_goal_id) do
    GenServer.call(__MODULE__, {:remove_dependency, goal_id, dependency_goal_id})
  end

  @spec link_nodes(binary(), [binary()]) :: {:ok, Goal.t()} | {:error, term()}
  def link_nodes(goal_id, node_ids) when is_binary(goal_id) and is_list(node_ids) do
    GenServer.call(__MODULE__, {:link_nodes, goal_id, node_ids})
  end

  @spec unlink_nodes(binary(), [binary()]) :: {:ok, Goal.t()} | {:error, term()}
  def unlink_nodes(goal_id, node_ids) when is_binary(goal_id) and is_list(node_ids) do
    GenServer.call(__MODULE__, {:unlink_nodes, goal_id, node_ids})
  end

  @spec set_progress(binary(), number()) :: {:ok, Goal.t()} | {:error, term()}
  def set_progress(goal_id, progress) when is_binary(goal_id) do
    GenServer.call(__MODULE__, {:set_progress, goal_id, progress})
  end

  @spec review_goal(binary(), map(), keyword()) :: {:ok, Goal.t(), map()} | {:error, term()}
  def review_goal(goal_id, signal, opts \\ [])
      when is_binary(goal_id) and is_map(signal) and is_list(opts) do
    GenServer.call(__MODULE__, {:review_goal, goal_id, signal, opts}, @review_goal_timeout_ms)
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:create_goal, attrs}, _from, state) do
    now = DateTime.utc_now()

    normalized = %{
      title: normalize_title(map_get(attrs, :title, "")),
      description: normalize_optional_string(map_get(attrs, :description, nil)),
      status: normalize_status(map_get(attrs, :status, :proposed)),
      timescale: normalize_timescale(map_get(attrs, :timescale, :short_term)),
      source_type: normalize_source_type(map_get(attrs, :source_type, :user)),
      priority: normalize_priority(map_get(attrs, :priority, :normal)),
      confidence: normalize_probability(map_get(attrs, :confidence, 0.5)),
      progress: normalize_probability(map_get(attrs, :progress, 0.0)),
      owner: normalize_optional_string(map_get(attrs, :owner, nil)),
      tags: normalize_string_list(map_get(attrs, :tags, [])),
      constraints: normalize_map(map_get(attrs, :constraints, %{})),
      success_criteria: normalize_map(map_get(attrs, :success_criteria, %{})),
      metadata: normalize_map(map_get(attrs, :metadata, %{})),
      linked_node_ids: normalize_string_list(map_get(attrs, :linked_node_ids, [])),
      parent_goal_id: normalize_optional_string(map_get(attrs, :parent_goal_id, nil)),
      created_at: normalize_datetime(map_get(attrs, :created_at, now), now),
      updated_at: normalize_datetime(map_get(attrs, :updated_at, now), now),
      due_at: normalize_datetime(map_get(attrs, :due_at, nil), nil),
      completed_at: normalize_datetime(map_get(attrs, :completed_at, nil), nil),
      last_reviewed_at: normalize_datetime(map_get(attrs, :last_reviewed_at, nil), nil)
    }

    normalized =
      normalized
      |> maybe_apply_create_completion_semantics()
      |> maybe_merge_id(attrs)

    reply =
      cond do
        normalized.title == "" ->
          {:error, {:validation_failed, :title_required}}

        true ->
          Store.insert_goal(normalized)
      end

    {:reply, reply, state}
  end

  def handle_call({:get_goal, goal_id}, _from, state) do
    {:reply, Store.get_goal(goal_id), state}
  end

  def handle_call({:list_goals, filters}, _from, state) do
    normalized_filters = normalize_filters(filters)

    reply =
      with {:ok, goals} <- Store.list_goals(normalized_filters.store_filters) do
        filtered =
          goals
          |> maybe_filter_by_timescale(normalized_filters.timescale)
          |> maybe_filter_by_parent(normalized_filters.parent_goal_id)
          |> maybe_filter_abandoned(normalized_filters.include_abandoned)

        {:ok, maybe_limit(filtered, normalized_filters.limit)}
      end

    {:reply, reply, state}
  end

  def handle_call({:update_goal, goal_id, attrs}, _from, state) do
    now = DateTime.utc_now()

    reply =
      with {:ok, existing} <- Store.get_goal(goal_id),
           {:ok, patch} <- build_update_patch(existing, attrs, now),
           {:ok, updated} <- Store.update_goal(goal_id, patch) do
        {:ok, updated}
      end

    {:reply, reply, state}
  end

  def handle_call({:delete_goal, goal_id}, _from, state) do
    {:reply, Store.delete_goal(goal_id), state}
  end

  def handle_call({:transition_goal, goal_id, to_status, extra_metadata}, _from, state) do
    now = DateTime.utc_now()

    reply =
      with {:ok, existing} <- Store.get_goal(goal_id),
           {:ok, next_status} <- normalize_status_checked(to_status),
           :ok <- validate_transition(existing.status, next_status) do
        merged_metadata =
          existing.metadata
          |> normalize_map()
          |> append_transition(existing.status, next_status, now, extra_metadata)

        patch =
          %{
            status: next_status,
            metadata: merged_metadata,
            updated_at: now
          }
          |> maybe_apply_transition_timestamps(next_status, now)

        Store.update_goal(goal_id, patch)
      end

    {:reply, reply, state}
  end

  def handle_call({:add_dependency, goal_id, dependency_goal_id}, _from, state) do
    now = DateTime.utc_now()

    reply =
      with {:ok, _dep_goal} <- Store.get_goal(dependency_goal_id),
           {:ok, goal} <- Store.get_goal(goal_id) do
        deps =
          goal.constraints
          |> normalize_map()
          |> Map.get("dependency_goal_ids", [])
          |> normalize_string_list()
          |> Kernel.++([dependency_goal_id])
          |> Enum.uniq()

        patch = %{
          constraints:
            goal.constraints
            |> normalize_map()
            |> Map.put("dependency_goal_ids", deps),
          updated_at: now
        }

        Store.update_goal(goal_id, patch)
      end

    {:reply, reply, state}
  end

  def handle_call({:remove_dependency, goal_id, dependency_goal_id}, _from, state) do
    now = DateTime.utc_now()

    reply =
      with {:ok, goal} <- Store.get_goal(goal_id) do
        deps =
          goal.constraints
          |> normalize_map()
          |> Map.get("dependency_goal_ids", [])
          |> normalize_string_list()
          |> Enum.reject(&(&1 == dependency_goal_id))

        patch = %{
          constraints:
            goal.constraints
            |> normalize_map()
            |> Map.put("dependency_goal_ids", deps),
          updated_at: now
        }

        Store.update_goal(goal_id, patch)
      end

    {:reply, reply, state}
  end

  def handle_call({:link_nodes, goal_id, node_ids}, _from, state) do
    now = DateTime.utc_now()
    node_ids = normalize_string_list(node_ids)

    reply =
      with {:ok, goal} <- Store.get_goal(goal_id) do
        linked = Enum.uniq(normalize_string_list(goal.linked_node_ids) ++ node_ids)

        patch = %{
          linked_node_ids: linked,
          updated_at: now
        }

        Store.update_goal(goal_id, patch)
      end

    {:reply, reply, state}
  end

  def handle_call({:unlink_nodes, goal_id, node_ids}, _from, state) do
    now = DateTime.utc_now()
    node_ids = MapSet.new(normalize_string_list(node_ids))

    reply =
      with {:ok, goal} <- Store.get_goal(goal_id) do
        linked =
          goal.linked_node_ids
          |> normalize_string_list()
          |> Enum.reject(&MapSet.member?(node_ids, &1))

        patch = %{
          linked_node_ids: linked,
          updated_at: now
        }

        Store.update_goal(goal_id, patch)
      end

    {:reply, reply, state}
  end

  def handle_call({:set_progress, goal_id, progress}, _from, state) do
    now = DateTime.utc_now()
    p = normalize_probability(progress)

    reply =
      with {:ok, goal} <- Store.get_goal(goal_id) do
        patch =
          %{
            progress: p,
            updated_at: now
          }
          |> maybe_auto_complete(goal.status, p, now)

        Store.update_goal(goal_id, patch)
      end

    {:reply, reply, state}
  end

  def handle_call({:review_goal, goal_id, signal, opts}, _from, state) do
    now = DateTime.utc_now()

    reply =
      with {:ok, goal} <- Store.get_goal(goal_id) do
        evaluation = Coverage.evaluate(signal, opts)

        review_meta =
          goal.metadata
          |> normalize_map()
          |> Map.put("last_coverage_review", %{
            "decision" => Atom.to_string(evaluation.decision),
            "decision_confidence" => evaluation.decision_confidence,
            "coverage_score" => evaluation.coverage_score,
            "uncertainty_score" => evaluation.uncertainty_score,
            "risk_score" => evaluation.risk_score,
            "computed_at" => DateTime.to_iso8601(evaluation.computed_at),
            "rationale" => evaluation.rationale
          })

        patch = %{
          metadata: review_meta,
          last_reviewed_at: now,
          updated_at: now
        }

        case Store.update_goal(goal_id, patch) do
          {:ok, updated_goal} -> {:ok, updated_goal, evaluation}
          {:error, reason} -> {:error, reason}
        end
      end

    {:reply, reply, state}
  end

  ## Build/validation helpers

  defp build_update_patch(existing, attrs, now) do
    title =
      if has_key?(attrs, :title) do
        attrs
        |> map_get(:title, existing.title)
        |> normalize_title()
      else
        existing.title
      end

    if title == "" do
      {:error, {:validation_failed, :title_required}}
    else
      patch = %{
        title: title,
        updated_at: now
      }

      patch =
        patch
        |> maybe_patch(:description, attrs, &normalize_optional_string/1)
        |> maybe_patch(:status, attrs, &normalize_status/1)
        |> maybe_patch(:timescale, attrs, &normalize_timescale/1)
        |> maybe_patch(:source_type, attrs, &normalize_source_type/1)
        |> maybe_patch(:priority, attrs, &normalize_priority/1)
        |> maybe_patch(:confidence, attrs, &normalize_probability/1)
        |> maybe_patch(:progress, attrs, &normalize_probability/1)
        |> maybe_patch(:owner, attrs, &normalize_optional_string/1)
        |> maybe_patch(:tags, attrs, &normalize_string_list/1)
        |> maybe_patch(:constraints, attrs, &normalize_map/1)
        |> maybe_patch(:success_criteria, attrs, &normalize_map/1)
        |> maybe_patch(:metadata, attrs, &normalize_map/1)
        |> maybe_patch(:linked_node_ids, attrs, &normalize_string_list/1)
        |> maybe_patch(:parent_goal_id, attrs, &normalize_optional_string/1)
        |> maybe_patch(:due_at, attrs, &normalize_datetime_optional/1)
        |> maybe_patch(:completed_at, attrs, &normalize_datetime_optional/1)
        |> maybe_patch(:last_reviewed_at, attrs, &normalize_datetime_optional/1)

      {:ok, patch}
    end
  end

  defp maybe_patch(patch, key, attrs, normalize_fun) do
    if has_key?(attrs, key) do
      Map.put(patch, key, attrs |> map_get(key, nil) |> normalize_fun.())
    else
      patch
    end
  end

  defp maybe_merge_id(normalized, attrs) do
    if has_key?(attrs, :id) do
      Map.put(normalized, :id, normalize_optional_string(map_get(attrs, :id, nil)))
    else
      normalized
    end
  end

  defp maybe_apply_create_completion_semantics(goal_attrs) do
    case goal_attrs.status do
      :completed ->
        goal_attrs
        |> Map.put(:progress, 1.0)
        |> Map.put(:completed_at, goal_attrs.completed_at || goal_attrs.updated_at)

      _ ->
        goal_attrs
    end
  end

  defp maybe_apply_transition_timestamps(patch, :completed, now) do
    patch
    |> Map.put(:completed_at, now)
    |> Map.put(:progress, 1.0)
  end

  defp maybe_apply_transition_timestamps(patch, _status, _now), do: patch

  defp maybe_auto_complete(patch, _current_status, progress, now) when progress >= 1.0 do
    patch
    |> Map.put(:status, :completed)
    |> Map.put(:completed_at, now)
  end

  defp maybe_auto_complete(patch, _current_status, _progress, _now), do: patch

  defp append_transition(metadata, from_status, to_status, at, extra) do
    extra = normalize_map(extra)

    transition = %{
      "from" => Atom.to_string(from_status),
      "to" => Atom.to_string(to_status),
      "at" => DateTime.to_iso8601(at)
    }

    metadata
    |> Map.update("transitions", [transition], fn t ->
      list = if is_list(t), do: t, else: []
      [transition | list]
    end)
    |> Map.merge(extra)
  end

  defp validate_transition(from, to) when from == to, do: :ok

  defp validate_transition(from, to) do
    allowed = Map.get(@transitions, from, [])

    if to in allowed do
      :ok
    else
      {:error, {:invalid_transition, from, to}}
    end
  end

  defp normalize_filters(filters) do
    limit = normalize_limit(map_get(filters, :limit, nil))

    %{
      timescale: normalize_timescale_optional(map_get(filters, :timescale, nil)),
      parent_goal_id: normalize_optional_string(map_get(filters, :parent_goal_id, nil)),
      include_abandoned: normalize_boolean(map_get(filters, :include_abandoned, false)),
      limit: limit,
      store_filters:
        %{}
        |> maybe_put_filter(:status, normalize_status_optional(map_get(filters, :status, nil)))
        |> maybe_put_filter(
          :priority,
          normalize_priority_optional(map_get(filters, :priority, nil))
        )
        |> maybe_put_filter(:owner, normalize_optional_string(map_get(filters, :owner, nil)))
        |> maybe_put_filter(:tag, normalize_optional_string(map_get(filters, :tag, nil)))
        |> maybe_put_filter(
          :min_progress,
          normalize_probability_optional(map_get(filters, :min_progress, nil))
        )
        |> maybe_put_filter(:limit, limit)
    }
  end

  defp maybe_put_filter(map, _key, nil), do: map
  defp maybe_put_filter(map, key, value), do: Map.put(map, key, value)

  defp maybe_filter_by_timescale(goals, nil), do: goals

  defp maybe_filter_by_timescale(goals, timescale),
    do: Enum.filter(goals, &(&1.timescale == timescale))

  defp maybe_filter_by_parent(goals, nil), do: goals

  defp maybe_filter_by_parent(goals, parent_goal_id),
    do: Enum.filter(goals, &(&1.parent_goal_id == parent_goal_id))

  defp maybe_filter_abandoned(goals, true), do: goals
  defp maybe_filter_abandoned(goals, false), do: Enum.reject(goals, &(&1.status == :abandoned))

  defp maybe_limit(goals, nil), do: goals
  defp maybe_limit(goals, limit) when is_integer(limit) and limit > 0, do: Enum.take(goals, limit)
  defp maybe_limit(goals, _), do: goals

  ## Normalizers

  defp normalize_status_checked(value) do
    status = normalize_status(value)

    if status in @valid_statuses do
      {:ok, status}
    else
      {:error, {:invalid_status, value}}
    end
  end

  defp normalize_status(value) when value in @valid_statuses, do: value

  defp normalize_status(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "active" -> :active
      "blocked" -> :blocked
      "completed" -> :completed
      "abandoned" -> :abandoned
      _ -> :proposed
    end
  end

  defp normalize_status(_), do: :proposed

  defp normalize_status_optional(nil), do: nil
  defp normalize_status_optional(value), do: normalize_status(value)

  defp normalize_timescale(value) when value in @valid_timescales, do: value

  defp normalize_timescale(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "immediate" -> :immediate
      "medium_term" -> :medium_term
      "long_term" -> :long_term
      _ -> :short_term
    end
  end

  defp normalize_timescale(_), do: :short_term

  defp normalize_timescale_optional(nil), do: nil
  defp normalize_timescale_optional(value), do: normalize_timescale(value)

  defp normalize_source_type(value) when value in @valid_sources, do: value

  defp normalize_source_type(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "system" -> :system
      "inferred" -> :inferred
      "policy" -> :policy
      _ -> :user
    end
  end

  defp normalize_source_type(_), do: :user

  defp normalize_priority(value) when value in @valid_priorities, do: value

  defp normalize_priority(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "low" -> :low
      "high" -> :high
      "critical" -> :critical
      _ -> :normal
    end
  end

  defp normalize_priority(_), do: :normal

  defp normalize_priority_optional(nil), do: nil
  defp normalize_priority_optional(value), do: normalize_priority(value)

  defp normalize_title(value) do
    value
    |> normalize_optional_string()
    |> Kernel.||("")
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) do
    value
    |> to_string()
    |> normalize_optional_string()
  end

  defp normalize_probability_optional(nil), do: nil
  defp normalize_probability_optional(value), do: normalize_probability(value)

  defp normalize_probability(value) when is_integer(value), do: normalize_probability(value * 1.0)

  defp normalize_probability(value) when is_float(value) do
    value
    |> max(0.0)
    |> min(1.0)
  end

  defp normalize_probability(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {f, _} -> normalize_probability(f)
      :error -> 0.0
    end
  end

  defp normalize_probability(_), do: 0.0

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_), do: %{}

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(fn
      v when is_binary(v) -> String.trim(v)
      v -> v |> to_string() |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_string_list(_), do: []

  defp normalize_datetime_optional(value), do: normalize_datetime(value, nil)

  defp normalize_datetime(nil, fallback), do: fallback
  defp normalize_datetime(%DateTime{} = dt, _fallback), do: dt

  defp normalize_datetime(value, fallback) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> fallback
    end
  end

  defp normalize_datetime(_value, fallback), do: fallback

  defp normalize_limit(nil), do: nil
  defp normalize_limit(value) when is_integer(value) and value > 0, do: value

  defp normalize_limit(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {i, _} when i > 0 -> i
      _ -> nil
    end
  end

  defp normalize_limit(_), do: nil

  defp normalize_boolean(value) when is_boolean(value), do: value

  defp normalize_boolean(value) when is_binary(value) do
    String.downcase(String.trim(value)) in ["1", "true", "yes", "y"]
  end

  defp normalize_boolean(_), do: false

  ## map helpers

  defp has_key?(map, key) when is_map(map) and is_atom(key) do
    Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))
  end

  defp map_get(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
