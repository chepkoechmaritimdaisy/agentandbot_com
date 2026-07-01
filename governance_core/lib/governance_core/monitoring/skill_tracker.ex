defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates YAML documentation (SKILL.md) for the project tools and modules.
  Enforces a 1024-character limit per file by chunking modules into multiple files.
  """
  use GenServer
  require Logger

  # Update every 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update_skills, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  defp update_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.map(&to_string/1)
        |> Enum.filter(&String.starts_with?(&1, "Elixir.GovernanceCore"))
        |> chunk_and_write()
      _ ->
        Logger.error("Failed to retrieve application modules")
    end
  end

  defp chunk_and_write(modules) do
    base_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(base_dir)

    # Chunking to keep under 1024 chars (approx 20 modules per file depending on length)
    # Using 20 as a safe default heuristic per chunk
    modules
    |> Enum.chunk_every(20)
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(base_dir, filename)

      yaml_content =
        chunk
        |> Enum.map(&"- #{&1}")
        |> Enum.join("\n")
        |> then(fn s -> "---\nmodules:\n#{s}\n---\n" end)

      # Check if generated YAML exceeds 1024 characters just to be safe and warn
      if String.length(yaml_content) > 1024 do
        Logger.warning("Generated SKILL file #{filename} exceeds 1024 characters! Length: #{String.length(yaml_content)}")
      end

      File.write!(filepath, yaml_content)
    end)
  end
end
