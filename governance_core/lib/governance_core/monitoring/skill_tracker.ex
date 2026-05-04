defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Dynamically manages tool documentation (SKILL.md) to universal standards.
  """
  use GenServer
  require Logger

  # Nightly interval
  @interval 24 * 60 * 60 * 1000

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
        generate_skill_files(modules)
      :undefined ->
        Logger.error("Failed to get modules for governance_core")
    end
  end

  defp generate_skill_files(modules) do
    priv_dir = Path.join(File.cwd!(), "priv")

    # Sort modules for deterministic output
    sorted_modules = Enum.sort(modules)

    chunk_and_write(sorted_modules, priv_dir, 1, [], 0)
  end

  defp chunk_and_write([], priv_dir, file_index, current_chunk, _current_length) do
    if current_chunk != [] do
      write_file(priv_dir, file_index, current_chunk)
    end
  end

  defp chunk_and_write([module | rest], priv_dir, file_index, current_chunk, current_length) do
    yaml_entry = module_to_yaml(module)
    entry_length = String.length(yaml_entry)

    header = if current_chunk == [], do: "---\nversion: 1.0\nskills:\n", else: ""
    header_length = String.length(header)

    if current_length + header_length + entry_length > 1024 and current_chunk != [] do
      # Write current chunk and start a new one
      write_file(priv_dir, file_index, current_chunk)
      chunk_and_write(rest, priv_dir, file_index + 1, [yaml_entry], String.length("---\nversion: 1.0\nskills:\n") + entry_length)
    else
      chunk_and_write(rest, priv_dir, file_index, current_chunk ++ [yaml_entry], current_length + header_length + entry_length)
    end
  end

  defp write_file(priv_dir, file_index, chunk) do
    filename = if file_index == 1, do: "SKILL.md", else: "SKILL_#{file_index}.md"
    filepath = Path.join(priv_dir, filename)

    content = "---\nversion: 1.0\nskills:\n" <> Enum.join(chunk, "")

    case File.write(filepath, content) do
      :ok -> Logger.info("Successfully updated #{filename}")
      {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
    end
  end

  defp module_to_yaml(module) do
    name = inspect(module)
    docs = get_docs(module)
    # Ensure multiline strings in YAML block scalars are indented
    indented_docs = String.replace(docs, "\n", "\n    ")

    """
      - name: #{name}
        description: |
          #{indented_docs}
    """
  end

  defp get_docs(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, :elixir, "text/markdown", %{"en" => docs}, _, _} -> docs
      _ -> "No documentation available."
    end
  end
end
