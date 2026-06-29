defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Monitors newly added tools and modules, dynamically generating
  or updating the SKILL.md documentation files in YAML format,
  enforcing a 1024-character limit per file.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 * 60 # Check every hour

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_skills, state) do
    update_skills()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_skills, @interval)
  end

  defp update_skills do
    Logger.debug("Updating SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Filter modules to focus on tools or core features if necessary
        # Here we just take all modules for demonstration
        docs = Enum.map(modules, fn mod ->
          "- module: #{inspect(mod)}\n  description: Automatically discovered module.\n"
        end)

        write_chunked_docs(docs, "SKILL")

      :undefined ->
        Logger.error("Failed to retrieve application modules.")
    end
  end

  defp write_chunked_docs(docs, base_name) do
    # Group docs into chunks that fit within 1024 characters
    chunks = chunk_by_length(docs, 1024, [], "")

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk, index} ->
      file_name = if index == 1, do: "#{base_name}.md", else: "#{base_name}_#{index}.md"
      file_path = Path.join(priv_dir, file_name)
      File.write!(file_path, chunk)
      Logger.debug("Wrote #{file_name}")
    end)
  end

  defp chunk_by_length([], _max_len, chunks, current_chunk) do
    if current_chunk != "", do: Enum.reverse([current_chunk | chunks]), else: Enum.reverse(chunks)
  end

  defp chunk_by_length([doc | rest], max_len, chunks, current_chunk) do
    if String.length(current_chunk) + String.length(doc) > max_len do
      chunk_by_length(rest, max_len, [current_chunk | chunks], doc)
    else
      chunk_by_length(rest, max_len, chunks, current_chunk <> doc)
    end
  end
end
