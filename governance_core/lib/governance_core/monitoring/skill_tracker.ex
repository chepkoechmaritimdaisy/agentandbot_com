defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Dynamically tracks and generates SKILL.md documentation
  for the tools and modules available in the application.
  """
  use GenServer
  require Logger

  # Update every hour
  @interval 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_update()
    {:ok, state}
  end

  @impl true
  def handle_info(:update, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def update_skills do
    Logger.info("Starting SKILL.md standardization update...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    docs = generate_yaml_docs(modules)

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    write_chunks(docs, priv_dir, 1, [])
  end

  defp generate_yaml_docs(modules) do
    Enum.map(modules, fn mod ->
      "- module: #{inspect(mod)}\n"
    end)
  end

  defp write_chunks([], priv_dir, index, current_chunk) do
    write_chunk_file(priv_dir, index, current_chunk)
  end

  defp write_chunks([doc | rest], priv_dir, index, current_chunk) do
    current_chunk_str = Enum.join(current_chunk, "")
    yaml_header = if Enum.empty?(current_chunk), do: "skills:\n", else: ""

    if String.length(current_chunk_str) + String.length(doc) + String.length(yaml_header) > 1024 do
      write_chunk_file(priv_dir, index, current_chunk)
      write_chunks([doc | rest], priv_dir, index + 1, [])
    else
      write_chunks(rest, priv_dir, index, current_chunk ++ [doc])
    end
  end

  defp write_chunk_file(_priv_dir, _index, []) do
    :ok
  end

  defp write_chunk_file(priv_dir, index, chunk) do
    filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
    filepath = Path.join(priv_dir, filename)

    content = "skills:\n" <> Enum.join(chunk, "")

    case File.write(filepath, content) do
      :ok ->
        Logger.info("Wrote SKILL document: #{filename}")
      {:error, reason} ->
        Logger.error("Failed to write #{filename}: #{inspect(reason)}")
    end
  end
end
