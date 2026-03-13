defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically detects newly added modules/functions and updates the SKILL.md
  documentation to reflect them in the background.
  """
  use GenServer
  require Logger

  @interval 60_000 # check every minute
  @skill_file "SKILL.md"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{known_modules: MapSet.new()}, name: __MODULE__)
  end

  def init(state) do
    # Load initially known modules to avoid writing all of them at startup
    known_modules = get_all_modules()
    schedule_check()
    {:ok, %{state | known_modules: known_modules}}
  end

  def handle_info(:check, state) do
    current_modules = get_all_modules()
    new_modules = MapSet.difference(current_modules, state.known_modules)

    if MapSet.size(new_modules) > 0 do
      Enum.each(new_modules, fn mod ->
        # We simulate auto-documentation for any new module detected
        tool_name = inspect(mod)
        desc = get_module_doc(mod)
        append_to_skill_md(tool_name, desc)
      end)
    end

    schedule_check()
    {:noreply, %{state | known_modules: current_modules}}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp get_all_modules do
    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(fn mod ->
      mod_name = inspect(mod)
      String.starts_with?(mod_name, "GovernanceCore")
    end)
    |> MapSet.new()
  end

  defp get_module_doc(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} ->
        doc

      _ ->
        "Automatically discovered internal module."
    end
  end

  defp append_to_skill_md(tool_name, description) do
    entry = """
    ---
    name: #{tool_name}
    created_at: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    ---
    # #{tool_name}

    #{description}
    """

    # Enforce 1024 character limit
    truncated_entry =
      if String.length(entry) > 1024 do
        String.slice(entry, 0, 1021) <> "..."
      else
        entry
      end

    content_to_write =
      if File.exists?(@skill_file) do
        "\n" <> truncated_entry
      else
        truncated_entry
      end

    File.write!(@skill_file, content_to_write, [:append])
    Logger.info("SkillTracker: Automatically added #{tool_name} to #{@skill_file}")
  end
end
