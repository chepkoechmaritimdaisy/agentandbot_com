defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates YAML-formatted SKILL.md documentation dynamically
  with chunks enforcing a strict 1024-character limit per file.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000
  @char_limit 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_tracking()
    {:ok, state}
  end

  def handle_info(:track, state) do
    perform_tracking()
    schedule_tracking()
    {:noreply, state}
  end

  defp schedule_tracking do
    Process.send_after(self(), :track, @interval)
  end

  def perform_tracking do
    Logger.info("Starting Skill Tracking...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        :undefined -> []
      end

    docs_data =
      Enum.map(modules, fn mod ->
        mod_name = inspect(mod)
        doc = get_moduledoc(mod)
        %{module: mod_name, doc: doc}
      end)

    chunks = chunk_docs(docs_data, [], "", 1)

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.each(chunks, fn {file_name, content} ->
      file_path = Path.join(priv_dir, file_name)
      case File.write(file_path, content) do
        :ok ->
          Logger.info("SkillTracker: Wrote #{file_name}")
        {:error, reason} ->
          Logger.error("SkillTracker: Failed to write #{file_name}: #{inspect(reason)}")
      end
    end)
  end

  defp get_moduledoc(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} ->
        # Ensure we only keep a brief summary if it's too long
        String.slice(doc, 0..100)
      _ ->
        "No documentation available."
    end
  end

  defp chunk_docs([], acc_chunks, current_content, file_idx) do
    if current_content != "" do
      file_name = if file_idx == 1, do: "SKILL.md", else: "SKILL_#{file_idx}.md"
      [{file_name, current_content} | acc_chunks]
    else
      acc_chunks
    end
  end

  defp chunk_docs([doc | rest], acc_chunks, current_content, file_idx) do
    yaml_item = """
    - module: #{doc.module}
      doc: |
        #{String.replace(doc.doc, "\n", "\n    ")}
    """

    if String.length(current_content) + String.length(yaml_item) > @char_limit do
      # Need a new file
      file_name = if file_idx == 1, do: "SKILL.md", else: "SKILL_#{file_idx}.md"
      acc_chunks = [{file_name, current_content} | acc_chunks]
      chunk_docs(rest, acc_chunks, yaml_item, file_idx + 1)
    else
      # Append to current content
      chunk_docs(rest, acc_chunks, current_content <> yaml_item, file_idx)
    end
  end
end
