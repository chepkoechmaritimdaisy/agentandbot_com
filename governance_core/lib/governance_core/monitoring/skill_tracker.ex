defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that discovers modules and generates YAML documentation to multiple files
  in the `priv` directory, enforcing a strict 1024-character limit per file.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 * 60 # 1 hour

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_update()
    {:ok, %{}}
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
    Logger.debug("Updating SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        priv_dir = :code.priv_dir(:governance_core)
        # Using File.cwd!() to match the requirement if application is not fully loaded/released
        # We will use Path.join(File.cwd!(), "priv") as explicitly stated in the memory
        priv_dir = Path.join(File.cwd!(), "priv")
        File.mkdir_p!(priv_dir)

        # Build list of strings representing each module
        entries = Enum.map(modules, fn mod ->
          "- module: #{inspect(mod)}\n"
        end)

        chunk_and_write(entries, priv_dir, 1, "", 0)

      _ ->
        Logger.error("Failed to retrieve modules for SKILL.md update")
    end
  end

  defp chunk_and_write([], priv_dir, index, current_yaml, _current_len) do
    write_file(priv_dir, index, current_yaml)
  end

  defp chunk_and_write([entry | rest], priv_dir, index, current_yaml, current_len) do
    entry_len = String.length(entry)

    if current_len + entry_len > 1024 do
      # Write current chunk and start a new one
      write_file(priv_dir, index, current_yaml)
      chunk_and_write(rest, priv_dir, index + 1, entry, entry_len)
    else
      chunk_and_write(rest, priv_dir, index, current_yaml <> entry, current_len + entry_len)
    end
  end

  defp write_file(priv_dir, index, yaml_content) do
    if yaml_content != "" do
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(priv_dir, filename)
      File.write!(filepath, yaml_content)
    end
  end
end
