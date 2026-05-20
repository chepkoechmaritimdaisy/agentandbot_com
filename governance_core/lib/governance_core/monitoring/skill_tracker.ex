defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  SkillTracker GenServer for automatically generating and managing
  SKILL.md documentation files for all project modules.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000
  @char_limit 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_update()
    {:ok, state}
  end

  @impl true
  def handle_info(:update_skills, state) do
    update_skill_docs()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  defp update_skill_docs do
    Logger.info("Updating SKILL.md docs...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    chunks = chunk_modules_by_length(modules, [])
    write_chunks_to_files(chunks)
  end

  defp chunk_modules_by_length([], acc), do: Enum.reverse(acc)
  defp chunk_modules_by_length(modules, acc) do
    {chunk, remaining} = take_chunk(modules, [], 0)
    chunk_modules_by_length(remaining, [chunk | acc])
  end

  defp take_chunk([], chunk, _len), do: {Enum.reverse(chunk), []}
  defp take_chunk([mod | rest], chunk, len) do
    # Calculate length of this module's YAML representation
    mod_yaml = generate_module_yaml(mod)
    mod_len = String.length(mod_yaml)

    if len + mod_len > @char_limit and chunk != [] do
      {Enum.reverse(chunk), [mod | rest]}
    else
      take_chunk(rest, [mod | chunk], len + mod_len)
    end
  end

  defp generate_module_yaml(mod) do
    """
    - module: #{inspect(mod)}
      description: |
        Auto-generated docs for #{inspect(mod)}
    """
  end

  defp write_chunks_to_files(chunks) do
    base_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(base_dir)

    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(base_dir, filename)

      yaml_content =
        chunk
        |> Enum.map(&generate_module_yaml/1)
        |> Enum.join("\n")

      case File.write(file_path, yaml_content) do
        :ok -> Logger.info("Wrote #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
