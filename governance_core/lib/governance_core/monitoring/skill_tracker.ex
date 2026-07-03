defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically discovers all application modules and updates the SKILL.md
  documentation in YAML format. Enforces a strict 1024 character limit
  per file by chunking data intelligently across multiple files.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # Run every hour
  @char_limit 1024

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
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Convert modules to basic skill representations
        skills = Enum.map(modules, fn mod ->
          %{
            "name" => inspect(mod),
            "type" => "module",
            "description" => "Provides #{inspect(mod)} functionality"
          }
        end)

        write_skill_files(skills)
      _ ->
        Logger.error("Failed to load modules for SKILL.md generation")
    end
  end

  defp write_skill_files(skills) do
    base_path = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(base_path)

    # Chunk the skills dynamically based on YAML output size
    chunks = chunk_by_size(skills, @char_limit, [])

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(base_path, filename)

      yaml_content = build_yaml(chunk)
      File.write!(file_path, yaml_content)
    end)

    Logger.info("Generated #{length(chunks)} SKILL.md files successfully.")
  end

  defp chunk_by_size([], _limit, acc), do: Enum.reverse(acc)
  defp chunk_by_size(skills, limit, acc) do
    {chunk, remaining} = take_chunk(skills, limit, [], 0)
    chunk_by_size(remaining, limit, [chunk | acc])
  end

  defp take_chunk([], _limit, current_chunk, _current_size), do: {Enum.reverse(current_chunk), []}
  defp take_chunk([skill | rest], limit, current_chunk, current_size) do
    skill_yaml = build_yaml([skill])
    skill_size = String.length(skill_yaml)

    # If adding this skill exceeds the limit (and we already have at least one), break
    if current_size + skill_size > limit and current_chunk != [] do
      {Enum.reverse(current_chunk), [skill | rest]}
    else
      take_chunk(rest, limit, [skill | current_chunk], current_size + skill_size)
    end
  end

  defp build_yaml(items) do
    yaml_lines = Enum.map(items, fn item ->
      """
      - name: #{item["name"]}
        type: #{item["type"]}
        description: #{item["description"]}
      """
    end)

    Enum.join(yaml_lines, "\n")
  end
end
