defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically updates SKILL.md files dynamically discovering modules
  and formatting them in YAML, respecting a strict 1024-character limit per file.
  """
  use GenServer
  require Logger

  # Update every 5 minutes
  @interval 5 * 60 * 1000
  @max_chars 1024

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
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  def perform_update do
    Logger.info("Updating SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.map(&to_string/1)
        |> Enum.filter(&String.starts_with?(&1, "Elixir.GovernanceCore"))
        |> format_and_chunk()
        |> write_files()
      _ ->
        Logger.error("Failed to retrieve modules for SKILL.md update")
    end
  end

  defp format_and_chunk(modules) do
    Enum.reduce(modules, [{[], 0}], fn mod, acc ->
      [{current_chunk, current_len} | rest] = acc

      # Minimal YAML entry
      entry = "- module: #{mod}\n"
      entry_len = String.length(entry)

      # +15 is roughly the size of "skills:\n" which we add to each file
      if current_len + entry_len + 15 > @max_chars do
        # Start a new chunk
        [{[entry], entry_len} | acc]
      else
        # Add to current chunk
        [{[entry | current_chunk], current_len + entry_len} | rest]
      end
    end)
    |> Enum.map(fn {chunk, _len} ->
      "skills:\n" <> Enum.join(Enum.reverse(chunk), "")
    end)
    |> Enum.reverse()
  end

  defp write_files(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(priv_dir, filename)

      case File.write(filepath, content) do
        :ok -> Logger.info("Updated #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
