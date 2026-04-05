defmodule Graphonomous.TemporalParser do
  @moduledoc """
  Parses relative date expressions from natural-language queries into absolute
  date windows, relative to a reference date.

  Used by the retriever to detect temporal intent for queries like "two weeks ago",
  "last Saturday", "last month" — producing a target date window that can be
  used to filter or boost candidate sessions by their event_date / document_date.

  Returns `{:ok, {Date.t, Date.t}}` where the tuple is a closed interval
  `{start_date, end_date}`, or `:none` when no relative-date phrase matches.
  """

  @word_numbers %{
    "one" => 1,
    "two" => 2,
    "three" => 3,
    "four" => 4,
    "five" => 5,
    "six" => 6,
    "seven" => 7,
    "eight" => 8,
    "nine" => 9,
    "ten" => 10,
    "eleven" => 11,
    "twelve" => 12,
    "a" => 1,
    "an" => 1
  }

  @weekdays %{
    "monday" => 1,
    "tuesday" => 2,
    "wednesday" => 3,
    "thursday" => 4,
    "friday" => 5,
    "saturday" => 6,
    "sunday" => 7
  }

  @doc """
  Parse a query string and return a relative date window relative to reference_date.

  Returns `{:ok, {start_date, end_date}}` on success, `:none` on no match.

  Examples (reference_date = 2023-04-10):
    iex> parse_relative_date("any tips for two weeks ago?", ~D[2023-04-10])
    {:ok, {~D[2023-03-24], ~D[2023-03-30]}}

    iex> parse_relative_date("what happened last Saturday?", ~D[2023-04-10])
    {:ok, {~D[2023-04-08], ~D[2023-04-08]}}
  """
  @spec parse_relative_date(String.t(), Date.t()) :: {:ok, {Date.t(), Date.t()}} | :none
  def parse_relative_date(query, reference_date) when is_binary(query) do
    q = String.downcase(query)

    cond do
      match = parse_n_units_ago(q, reference_date) -> {:ok, match}
      match = parse_last_weekday(q, reference_date) -> {:ok, match}
      match = parse_last_period(q, reference_date) -> {:ok, match}
      match = parse_this_period(q, reference_date) -> {:ok, match}
      match = parse_yesterday(q, reference_date) -> {:ok, match}
      true -> :none
    end
  end

  def parse_relative_date(_, _), do: :none

  # "N weeks ago" / "two weeks ago" / "a month ago"
  defp parse_n_units_ago(q, ref) do
    re =
      ~r/\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|a|an)\s+(day|week|month|year)s?\s+ago\b/

    case Regex.run(re, q) do
      [_, n_str, unit] ->
        n = word_to_int(n_str)
        days = unit_to_days(unit) * n
        target = Date.add(ref, -days)
        # ±3-day soft window
        {Date.add(target, -3), Date.add(target, 3)}

      _ ->
        nil
    end
  end

  # "last Saturday" / "last Sunday" etc. — the most recent prior occurrence
  defp parse_last_weekday(q, ref) do
    re = ~r/\blast\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/

    case Regex.run(re, q) do
      [_, day_name] ->
        target_dow = Map.fetch!(@weekdays, day_name)
        ref_dow = Date.day_of_week(ref)
        diff = rem(ref_dow - target_dow + 7, 7)
        diff = if diff == 0, do: 7, else: diff
        target = Date.add(ref, -diff)
        {target, target}

      _ ->
        nil
    end
  end

  # "last week" (previous ISO week), "last weekend", "last month", "last year"
  defp parse_last_period(q, ref) do
    cond do
      Regex.match?(~r/\blast\s+weekend\b/, q) ->
        # Previous Saturday-Sunday pair
        ref_dow = Date.day_of_week(ref)
        last_sat_diff = rem(ref_dow - 6 + 7, 7)
        last_sat_diff = if last_sat_diff == 0, do: 7, else: last_sat_diff
        sat = Date.add(ref, -last_sat_diff)
        sun = Date.add(sat, 1)
        {sat, sun}

      Regex.match?(~r/\blast\s+week\b/, q) ->
        # 7-14 days prior
        {Date.add(ref, -14), Date.add(ref, -7)}

      Regex.match?(~r/\blast\s+month\b/, q) ->
        {Date.add(ref, -37), Date.add(ref, -23)}

      Regex.match?(~r/\blast\s+year\b/, q) ->
        {Date.add(ref, -400), Date.add(ref, -330)}

      true ->
        nil
    end
  end

  # "this week/month/year"
  defp parse_this_period(q, ref) do
    cond do
      Regex.match?(~r/\bthis\s+week\b/, q) ->
        {Date.add(ref, -7), ref}

      Regex.match?(~r/\bthis\s+month\b/, q) ->
        {Date.add(ref, -30), ref}

      Regex.match?(~r/\bthis\s+year\b/, q) ->
        {Date.add(ref, -365), ref}

      true ->
        nil
    end
  end

  defp parse_yesterday(q, ref) do
    if Regex.match?(~r/\byesterday\b/, q) do
      target = Date.add(ref, -1)
      {target, target}
    else
      nil
    end
  end

  defp word_to_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> Map.get(@word_numbers, s, 1)
    end
  end

  defp unit_to_days("day"), do: 1
  defp unit_to_days("week"), do: 7
  defp unit_to_days("month"), do: 30
  defp unit_to_days("year"), do: 365

  @doc """
  Parse the longmemeval question_date / haystack_date string into a Date.

  Format: "2023/04/10 (Mon) 17:50" → ~D[2023-04-10].
  Falls back to ISO 8601 parsing.
  """
  @spec parse_session_date(String.t() | nil) :: Date.t() | nil
  def parse_session_date(nil), do: nil

  def parse_session_date(str) when is_binary(str) do
    cond do
      match = Regex.run(~r/^(\d{4})\/(\d{1,2})\/(\d{1,2})/, str) ->
        [_, y, m, d] = match
        safe_date(String.to_integer(y), String.to_integer(m), String.to_integer(d))

      match = Regex.run(~r/^(\d{4})-(\d{1,2})-(\d{1,2})/, str) ->
        [_, y, m, d] = match
        safe_date(String.to_integer(y), String.to_integer(m), String.to_integer(d))

      true ->
        nil
    end
  end

  def parse_session_date(_), do: nil

  defp safe_date(y, m, d) do
    case Date.new(y, m, d) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  @doc """
  Check whether a candidate date falls within a target date window.
  """
  @spec date_in_window?(Date.t() | nil, {Date.t(), Date.t()}) :: boolean()
  def date_in_window?(nil, _), do: false

  def date_in_window?(%Date{} = candidate, {%Date{} = start_d, %Date{} = end_d}) do
    Date.compare(candidate, start_d) != :lt and Date.compare(candidate, end_d) != :gt
  end

  def date_in_window?(_, _), do: false
end
