defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that dynamically discovers modules and generates YAML documentation (SKILL.md)
  according to universal standards (1024-character limit per file).
  """
  use GenServer
  require Logger

  # Default interval for generating docs
  @interval 60 * 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_update()
    {:ok, %{}}
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
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        generate_docs(modules)
      _ ->
        Logger.error("Failed to retrieve modules for SkillTracker.")
    end
  end

  defp generate_docs(modules) do
    # Filter modules to get a meaningful subset or all
    docs =
      modules
      |> Enum.map(fn mod ->
        # Simple representation for documentation
        %{module: inspect(mod), description: "Auto-generated documentation for #{inspect(mod)}"}
      end)

    # Convert to YAML format strings conceptually, we will construct simple YAML
    yaml_entries = Enum.map(docs, fn doc ->
      "- module: #{doc.module}\n  description: #{doc.description}\n"
    end)

    chunk_and_write(yaml_entries, 1, [], 0)
  end

  defp chunk_and_write([], _file_index, [], _current_len), do: :ok
  defp chunk_and_write([], file_index, current_chunk, _current_len) do
    write_chunk(file_index, current_chunk)
  end
  defp chunk_and_write([entry | rest], file_index, current_chunk, current_len) do
    entry_len = String.length(entry)
    if current_len + entry_len > 1024 and current_chunk != [] do
      write_chunk(file_index, current_chunk)
      chunk_and_write(rest, file_index + 1, [entry], entry_len)
    else
      chunk_and_write(rest, file_index, current_chunk ++ [entry], current_len + entry_len)
    end
  end

  defp write_chunk(file_index, chunk) do
    filename = if file_index == 1, do: "SKILL.md", else: "SKILL_#{file_index}.md"
    path = Path.join(File.cwd!(), "priv/" <> filename)
    content = Enum.join(chunk, "")
    File.write!(path, content)
    Logger.info("Generated #{filename}")
  end
end
