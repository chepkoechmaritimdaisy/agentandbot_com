defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that dynamically manages tool documentation (`SKILL.md`) by discovering modules.
  It chunks the output to multiple YAML files ensuring each is within the 1024 character limit.
  """
  use GenServer
  require Logger

  # Runs periodically (e.g., every 15 minutes)
  @interval 15 * 60 * 1000
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
    Logger.info("Starting SkillTracker documentation update...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    docs = extract_docs(modules)
    yaml_chunks = build_yaml_chunks(docs)

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    write_chunks(yaml_chunks, priv_dir, 1)
  end

  defp extract_docs(modules) do
    Enum.reduce(modules, [], fn mod, acc ->
      case Code.fetch_docs(mod) do
        {:docs_v1, _, :elixir, _, %{"en" => mod_doc}, _, _} ->
          [%{module: inspect(mod), doc: mod_doc} | acc]
        _ ->
          acc
      end
    end)
  end

  defp build_yaml_chunks(docs) do
    # Chunk based on dynamically calculated yaml string length
    {chunks, current_chunk, _current_len} =
      Enum.reduce(docs, {[], [], 0}, fn item, {all_chunks, current_chunk, current_len} ->
        item_yaml = format_item(item)
        item_len = String.length(item_yaml)

        if current_len + item_len > @max_chars and current_chunk != [] do
          # Push current chunk and start a new one
          {[Enum.reverse(current_chunk) | all_chunks], [item], item_len}
        else
          {all_chunks, [item | current_chunk], current_len + item_len}
        end
      end)

    chunks = if current_chunk != [], do: [Enum.reverse(current_chunk) | chunks], else: chunks
    Enum.reverse(chunks)
  end

  defp format_item(%{module: mod, doc: doc}) do
    indented_doc =
      doc
      |> String.split("\n")
      |> Enum.map(fn line -> "    " <> line end)
      |> Enum.join("\n")

    """
    - module: #{mod}
      description: |
    #{indented_doc}
    """
  end

  defp write_chunks([], _dir, _index), do: :ok

  defp write_chunks([chunk | rest], dir, index) do
    filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
    path = Path.join(dir, filename)

    yaml_content =
      chunk
      |> Enum.map(&format_item/1)
      |> Enum.join("")

    case File.write(path, yaml_content) do
      :ok -> Logger.info("Written #{filename} to #{path}")
      {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
    end

    write_chunks(rest, dir, index + 1)
  end
end
