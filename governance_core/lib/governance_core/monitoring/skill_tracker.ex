defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically discovers all application modules and writes them to SKILL.md
  in the priv directory in YAML format, ensuring no single file exceeds 1024 characters.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour
  @max_chars 1024

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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
        yaml_lines = format_modules_to_yaml(modules)
        chunks = chunk_yaml_lines(yaml_lines, @max_chars)
        write_skill_files(chunks)
      _ ->
        Logger.error("Failed to retrieve modules for SkillTracker")
    end
  end

  defp format_modules_to_yaml(modules) do
    ["skills:"] ++ Enum.map(modules, fn mod -> "  - #{inspect(mod)}" end)
  end

  defp chunk_yaml_lines(lines, max_chars) do
    Enum.reduce(lines, [{0, []}], fn line, acc ->
      [{current_len, current_chunk} | rest] = acc
      line_len = String.length(line) + 1 # +1 for newline

      if current_len + line_len > max_chars and not Enum.empty?(current_chunk) do
        [{line_len, [line]} | acc]
      else
        [{current_len + line_len, [line | current_chunk]} | rest]
      end
    end)
    |> Enum.map(fn {_, chunk} -> Enum.reverse(chunk) |> Enum.join("\n") end)
    |> Enum.reverse()
  end

  defp write_skill_files(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(priv_dir, filename)
      File.write!(file_path, chunk)
    end)
    Logger.info("SkillTracker: Updated SKILL.md files")
  end
end
