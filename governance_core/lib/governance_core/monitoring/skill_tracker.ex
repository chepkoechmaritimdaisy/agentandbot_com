defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically discovers application modules and generates standard SKILL.md documentation
  in YAML format, chunking files to stay under the 1024-character limit.
  """
  use GenServer
  require Logger

  # Update every 10 minutes
  @interval 10 * 60 * 1000
  @max_chars 1024

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
    Logger.info("SkillTracker: Updating SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Filter modules relevant to logic/features
        relevant_modules = Enum.filter(modules, fn mod ->
          name = to_string(mod)
          not String.contains?(name, "Web") and not String.starts_with?(name, "Elixir.GovernanceCoreWeb")
        end)

        generate_skill_docs(relevant_modules)
      :undefined ->
        Logger.error("SkillTracker: Could not discover application modules.")
    end
  end

  defp generate_skill_docs(modules) do
    base_dir = Path.join(File.cwd!(), "priv")

    # Ensure priv directory exists
    File.mkdir_p!(base_dir)

    # Build intermediate skill representation
    skills = Enum.map(modules, fn mod ->
      module_name = to_string(mod) |> String.replace_prefix("Elixir.", "")

      docs = case Code.fetch_docs(mod) do
        {:docs_v1, _, :elixir, "text/markdown", %{"en" => doc_text}, _, _} ->
          doc_text
        _ ->
          "No documentation available."
      end

      # Just taking a summary to save space
      summary = docs |> String.split("\n") |> List.first() || ""

      %{
        "name" => module_name,
        "description" => summary
      }
    end)

    # Chunk and write YAML files
    write_chunks(skills, base_dir, 1, [], 0)
  end

  defp write_chunks([], base_dir, file_index, current_chunk, _current_length) do
    if current_chunk != [] do
      write_file(base_dir, file_index, current_chunk)
    end
  end

  defp write_chunks([skill | rest], base_dir, file_index, current_chunk, current_length) do
    # Encode just this skill to measure its length
    skill_yaml = Jason.encode!(skill) # Or use a YAML library, but Jason is available and fast enough for simple structs or we can manually build YAML string
    # Manually build simple YAML to ensure format
    skill_yaml_str = """
    - name: "#{skill["name"]}"
      description: "#{escape_yaml_string(skill["description"])}"
    """

    added_length = String.length(skill_yaml_str)

    if current_length + added_length > @max_chars and current_chunk != [] do
      # Current chunk is full, write it and start a new one
      write_file(base_dir, file_index, current_chunk)
      write_chunks(rest, base_dir, file_index + 1, [skill_yaml_str], added_length)
    else
      # Add to current chunk
      write_chunks(rest, base_dir, file_index, current_chunk ++ [skill_yaml_str], current_length + added_length)
    end
  end

  defp write_file(base_dir, 1, chunk) do
    path = Path.join(base_dir, "SKILL.md")
    content = Enum.join(chunk, "")
    File.write!(path, content)
  end

  defp write_file(base_dir, index, chunk) do
    path = Path.join(base_dir, "SKILL_#{index}.md")
    content = Enum.join(chunk, "")
    File.write!(path, content)
  end

  defp escape_yaml_string(str) do
    str
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", " ")
  end
end
