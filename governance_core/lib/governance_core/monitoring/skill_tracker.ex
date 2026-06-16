defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that dynamically manages SKILL.md documentation
  according to universal standards (1024 character limit, YAML format).
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

  def handle_info(:update, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def update_skills do
    Logger.info("Updating SKILL.md documentation...")

    # Discover all modules in the application
    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    formatted_modules = format_modules(modules)

    # Write to files in chunks to enforce 1024-character limit
    chunk_and_write(formatted_modules)
  end

  defp format_modules(modules) do
    Enum.map(modules, fn mod ->
      "- module: #{inspect(mod)}\n"
    end)
  end

  defp chunk_and_write(formatted_modules) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    do_chunk(formatted_modules, 1, "", [])
  end

  defp do_chunk([], file_index, current_content, _acc) do
    if current_content != "" do
      write_file(file_index, current_content)
    end
  end

  defp do_chunk([module_str | rest], file_index, current_content, acc) do
    # Calculate length if we add the next module
    # Include YAML header if it's empty
    header = if current_content == "", do: "---\nskills:\n", else: ""

    new_content = current_content <> header <> module_str

    if String.length(new_content) > 1024 do
      # Write current content to file and start a new one
      if current_content != "" do
        write_file(file_index, current_content)
      end
      do_chunk(rest, file_index + 1, "---\nskills:\n" <> module_str, acc)
    else
      # Continue adding to the current chunk
      do_chunk(rest, file_index, new_content, acc)
    end
  end

  defp write_file(index, content) do
    filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
    file_path = Path.join(Path.join(File.cwd!(), "priv"), filename)

    case File.write(file_path, content) do
      :ok -> Logger.info("Successfully wrote #{filename}")
      {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
    end
  end
end
