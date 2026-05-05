defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically queries the application for available modules/tools
  and updates SKILL.md files in the `priv/` directory, adhering
  to formatting constraints (e.g., max 1024 chars per YAML file).
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000
  @max_chars 1024

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

  def perform_update do
    Logger.debug("Starting SKILL.md standardization update...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    chunks = chunk_modules(modules)

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {yaml_content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(priv_dir, filename)

      case File.write(filepath, yaml_content) do
        :ok -> Logger.debug("Successfully updated #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp chunk_modules(modules) do
    do_chunk(modules, [], [], 0)
  end

  defp do_chunk([], current_chunk, all_chunks, _current_len) do
    if Enum.empty?(current_chunk) do
      Enum.reverse(all_chunks)
    else
      Enum.reverse([generate_yaml(Enum.reverse(current_chunk)) | all_chunks])
    end
  end

  defp do_chunk([mod | rest], current_chunk, all_chunks, current_len) do
    mod_yaml = format_module(mod)
    mod_len = String.length(mod_yaml)

    if current_len + mod_len > @max_chars and not Enum.empty?(current_chunk) do
      # Finish current chunk and start a new one
      chunk_yaml = generate_yaml(Enum.reverse(current_chunk))
      do_chunk(rest, [mod_yaml], [chunk_yaml | all_chunks], mod_len)
    else
      # Add to current chunk
      do_chunk(rest, [mod_yaml | current_chunk], all_chunks, current_len + mod_len)
    end
  end

  defp format_module(mod) do
    name = inspect(mod)
    desc = "Module for #{name}"

    # Properly format YAML block scalar with indentation
    """
    - name: #{name}
      description: |
        #{desc}
    """
  end

  defp generate_yaml(modules_yaml_list) do
    "skills:\n" <> Enum.join(modules_yaml_list, "")
  end
end
