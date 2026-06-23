defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates and updates SKILL.md documentation dynamically based on discovered
  modules in the project, formatted in YAML, with a strict 1024 character limit per file.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update_skills, state) do
    update_skill_docs()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  defp update_skill_docs do
    Logger.info("Updating SKILL.md documentation...")

    {:ok, modules} = :application.get_key(:governance_core, :modules)

    # Filter and map modules to simple structures
    skill_data = Enum.map(modules, fn mod ->
      %{
        "module" => inspect(mod),
        "description" => "Dynamically discovered module in GovernanceCore."
      }
    end)

    chunk_and_write(skill_data)
  end

  defp chunk_and_write(skill_data) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    # We need to build YAML strings and ensure each file is <= 1024 chars
    chunks = chunk_by_length(skill_data, 1024, [], [])

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {yaml_string, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(priv_dir, filename)

      File.write!(file_path, "---\n" <> yaml_string)
      Logger.info("Wrote #{filename}")
    end)
  end

  defp chunk_by_length([], _limit, current_chunk, all_chunks) do
    final_chunks = if current_chunk == [], do: all_chunks, else: [current_chunk | all_chunks]

    Enum.reverse(final_chunks)
    |> Enum.map(fn chunk ->
      # Convert the list of maps to a YAML-like string
      Enum.map(chunk, fn item ->
        "- module: #{item["module"]}\n  description: #{item["description"]}\n"
      end)
      |> Enum.join("")
    end)
  end

  defp chunk_by_length([item | rest], limit, current_chunk, all_chunks) do
    # Approximate length of the item when converted to YAML
    item_yaml = "- module: #{item["module"]}\n  description: #{item["description"]}\n"
    item_len = String.length(item_yaml)

    current_chunk_yaml = Enum.map(current_chunk, fn i -> "- module: #{i["module"]}\n  description: #{i["description"]}\n" end) |> Enum.join("")
    current_len = String.length(current_chunk_yaml)

    # Add 4 for "---\n" header
    if current_len + item_len + 4 > limit do
      chunk_by_length(rest, limit, [item], [current_chunk | all_chunks])
    else
      chunk_by_length(rest, limit, current_chunk ++ [item], all_chunks)
    end
  end
end
