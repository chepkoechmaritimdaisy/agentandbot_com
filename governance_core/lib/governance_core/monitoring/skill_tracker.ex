defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically tracks and updates SKILL.md documentation for tools/modules
  in the project. Ensures standard formatting and 1024 char limit.
  """

  use GenServer
  require Logger

  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update, state) do
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp perform_update do
    Logger.info("Starting SkillTracker Update...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Just creating a mock list of tools based on modules for the skill list
        tools_list = Enum.map(Enum.take(modules, 10), fn m -> "- #{inspect(m)}" end) |> Enum.join("\n")

        # Enforce 1024 char limit and truncate at the last newline
        content = String.slice(tools_list, 0..1023)
        content = String.replace(content, ~r/\n[^\n]*$/, "")

        # Indent line-by-line in Elixir
        indented_content =
          content
          |> String.split("\n")
          |> Enum.map(fn line -> "  " <> line end)
          |> Enum.join("\n")

        yaml = """
        skills: |
        #{indented_content}
        """

        file_path = Path.join(:code.priv_dir(:governance_core), "SKILL.md")

        case File.write(file_path, yaml) do
          :ok -> Logger.info("SkillTracker successfully updated #{file_path}")
          {:error, reason} -> Logger.warning("SkillTracker failed to update #{file_path}: #{inspect(reason)}")
        end

      _ ->
        Logger.error("SkillTracker failed to retrieve modules.")
    end
  end
end
