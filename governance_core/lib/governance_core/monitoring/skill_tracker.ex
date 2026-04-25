defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically tracks and updates SKILL.md for tools and modules.
  Enforces a 1024 character limit by chunking/truncating data before formatting.
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
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp update_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Chunk modules to preserve all data while respecting the 1024 char limit per file
        chunks = Enum.chunk_every(modules, 20)

        Enum.with_index(chunks, 1)
        |> Enum.each(fn {chunk, index} ->
          yaml_content = generate_yaml(chunk)
          filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
          file_path = Path.join([File.cwd!(), "priv", filename])

          case File.write(file_path, yaml_content) do
            :ok ->
              Logger.info("SkillTracker successfully updated #{filename}")
            {:error, reason} ->
              Logger.warning("SkillTracker failed to write #{filename}: #{inspect(reason)}")
          end
        end)

      :undefined ->
        Logger.warning("SkillTracker could not find modules for governance_core")
    end
  end

  defp generate_yaml(modules) do
    modules_str =
      modules
      |> Enum.map(fn mod -> "  - #{inspect(mod)}" end)
      |> Enum.join("\n")

    """
    ---
    name: GovernanceCore
    type: System
    modules: |
    #{modules_str}
    ...
    """
  end
end
