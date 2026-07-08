defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically tracks modules and updates SKILL.md documentation
  ensuring files do not exceed 1024 characters.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

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
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def perform_update do
    Logger.info("SkillTracker: Updating SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> format_modules_as_yaml()
        |> chunk_and_write()
      _ ->
        Logger.warning("SkillTracker: Could not get modules from application")
    end
  end

  defp format_modules_as_yaml(modules) do
    # Simple formatting of modules to string lines
    Enum.map(modules, fn mod -> "- #{inspect(mod)}\n" end)
  end

  defp chunk_and_write(yaml_lines) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    # Max 1024 chars per file
    chunks = group_lines(yaml_lines, [], 0, 1024)

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk_lines, index} ->
      filename = if index == 1 do
        "SKILL.md"
      else
        "SKILL_#{index}.md"
      end

      filepath = Path.join(priv_dir, filename)
      content = "skills:\n" <> Enum.join(chunk_lines)

      File.write!(filepath, content)
      Logger.debug("SkillTracker: Wrote #{filepath}")
    end)
  end

  defp group_lines([], current_chunk, _current_length, _max_length) do
    if current_chunk == [] do
      []
    else
      [Enum.reverse(current_chunk)]
    end
  end

  defp group_lines([line | rest], current_chunk, current_length, max_length) do
    line_length = String.length(line)
    # 8 is for length of "skills:\n"
    header_length = if current_chunk == [], do: 8, else: 0

    if current_length + header_length + line_length > max_length do
      # Start a new chunk
      [Enum.reverse(current_chunk) | group_lines([line | rest], [], 0, max_length)]
    else
      group_lines(rest, [line | current_chunk], current_length + header_length + line_length, max_length)
    end
  end
end
