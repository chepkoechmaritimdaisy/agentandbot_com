defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer to dynamically track and document tools.
  Generates YAML files documenting the modules, chunking them to enforce a strict
  1024-character limit per file by dynamically calculating the actual YAML length.
  """
  use GenServer
  require Logger

  # Update interval in milliseconds
  @interval 60 * 60 * 1000

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

  def update_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.map(&extract_skill/1)
        |> Enum.reject(&is_nil/1)
        |> generate_yaml_chunks()
        |> write_files()

      :undefined ->
        Logger.error("Failed to get modules for governance_core")
    end
  end

  defp extract_skill(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, :elixir, "text/markdown", %{"en" => doc}, _, _} ->
        %{
          "module" => inspect(module),
          "description" => doc
        }

      _ ->
        nil
    end
  end

  defp generate_yaml_chunks(skills) do
    # Group skills into chunks that fit within 1024 characters when encoded as YAML
    Enum.reduce(skills, [%{yaml: "", size: 0, items: []}], fn skill, acc ->
      [current_chunk | rest] = acc

      skill_yaml = format_skill_yaml(skill)
      skill_size = String.length(skill_yaml)

      if current_chunk.size + skill_size > 1024 and current_chunk.size > 0 do
        # Start a new chunk
        new_chunk = %{yaml: skill_yaml, size: skill_size, items: [skill]}
        [new_chunk, current_chunk | rest]
      else
        # Add to current chunk
        updated_chunk = %{
          yaml: current_chunk.yaml <> skill_yaml,
          size: current_chunk.size + skill_size,
          items: [skill | current_chunk.items]
        }
        [updated_chunk | rest]
      end
    end)
    |> Enum.reverse()
  end

  defp format_skill_yaml(skill) do
    """
    - module: #{skill["module"]}
      description: |
    #{indent_string(skill["description"], 4)}
    """
  end

  defp indent_string(string, spaces) do
    indent = String.duplicate(" ", spaces)
    string
    |> String.split("\n")
    |> Enum.map(fn line -> indent <> line end)
    |> Enum.join("\n")
  end

  defp write_files(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.each(Enum.with_index(chunks), fn {chunk, index} ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      file_path = Path.join(priv_dir, filename)

      case File.write(file_path, chunk.yaml) do
        :ok ->
          Logger.info("SkillTracker wrote #{filename}")

        {:error, reason} ->
          Logger.error("SkillTracker failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
