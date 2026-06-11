defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates and updates SKILL.md documentation based on discovered modules.
  Enforces a 1024-character limit per generated YAML file.
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

  def handle_info(:update, state) do
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def perform_update do
    Logger.debug("Starting SkillTracker update...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Generate YAML representations for modules
        module_docs = Enum.map(modules, &format_module/1)

        # Chunk the strings so each file is under @char_limit
        chunks = chunk_docs(module_docs, [], "", 0)

        # Write each chunk to a file
        Enum.with_index(chunks, 1)
        |> Enum.each(fn {content, index} ->
          filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
          file_path = Path.join(File.cwd!(), "priv/#{filename}")

          case File.write(file_path, content) do
            :ok -> Logger.debug("SkillTracker successfully wrote #{filename}")
            {:error, reason} -> Logger.error("SkillTracker failed to write #{filename}: #{inspect(reason)}")
          end
        end)

      _ ->
        Logger.error("SkillTracker could not load modules for :governance_core")
    end
  end

  defp format_module(module) do
    # Simple YAML representation
    """
    - module: #{inspect(module)}
      description: Auto-generated documentation for #{inspect(module)}
    """
  end

  # Group module YAML strings so their combined length is < 1024 chars
  defp chunk_docs([], acc_chunks, current_chunk, _current_len) do
    Enum.reverse([current_chunk | acc_chunks])
  end

  defp chunk_docs([doc | rest], acc_chunks, current_chunk, current_len) do
    doc_len = String.length(doc)

    if current_len + doc_len > @char_limit do
      # Start a new chunk
      chunk_docs(rest, [current_chunk | acc_chunks], doc, doc_len)
    else
      # Append to current chunk
      new_chunk = current_chunk <> doc
      chunk_docs(rest, acc_chunks, new_chunk, current_len + doc_len)
    end
  end
end
