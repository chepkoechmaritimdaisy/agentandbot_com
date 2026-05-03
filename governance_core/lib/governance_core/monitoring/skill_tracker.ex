defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates and updates SKILL.md documentation in YAML format for all available application modules.
  Enforces a 1024 character limit per file by chunking.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @char_limit 1024

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
    Logger.debug("Generating SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.map(&module_to_yaml/1)
        |> chunk_yaml_docs()
        |> write_skills_files()
      _ ->
        Logger.error("Failed to retrieve modules for governance_core application")
    end
  end

  defp module_to_yaml(module) do
    module_name = inspect(module)
    """
    - name: "#{module_name}"
      description: |
        Module #{module_name} in GovernanceCore.
    """
  end

  defp chunk_yaml_docs(yaml_strings) do
    Enum.reduce(yaml_strings, [%{content: "skills:\n", length: 8}], fn yaml_str, chunks ->
      current_chunk = List.last(chunks)
      yaml_len = String.length(yaml_str)

      if current_chunk.length + yaml_len > @char_limit do
        chunks ++ [%{content: "skills:\n" <> yaml_str, length: 8 + yaml_len}]
      else
        updated_chunk = %{
          content: current_chunk.content <> yaml_str,
          length: current_chunk.length + yaml_len
        }
        List.replace_at(chunks, -1, updated_chunk)
      end
    end)
    |> Enum.map(&(&1.content))
  end

  defp write_skills_files(chunks) do
    base_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(base_dir)

    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(base_dir, filename)

      case File.write(filepath, content) do
        :ok ->
          Logger.debug("Wrote #{filepath}")
        {:error, reason} ->
          Logger.error("Failed to write #{filepath}: #{inspect(reason)}")
      end
    end)
  end
end
