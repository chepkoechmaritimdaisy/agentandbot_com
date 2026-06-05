defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that periodically discovers application modules and generates
  SKILL.md documentation in YAML format, chunking files to strictly adhere
  to a 1024-character limit per file, and saving them in the `priv/` source directory.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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
    generate_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp generate_skills do
    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    chunks = chunk_modules(modules, [])

    # Write chunks to source priv directory
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {yaml_content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(priv_dir, filename)

      case File.write(filepath, yaml_content) do
        :ok -> Logger.info("Wrote #{filename} successfully")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp chunk_modules([], acc), do: Enum.reverse(acc)
  defp chunk_modules(remaining_modules, acc) do
    {chunk, next_remaining} = take_while_fits(remaining_modules, [], 0)
    yaml = to_yaml(chunk)
    chunk_modules(next_remaining, [yaml | acc])
  end

  # Header length:
  # "modules:\n" is 9 chars.
  # We start calculating length with that.
  defp take_while_fits([], current_chunk, _current_len) do
    {Enum.reverse(current_chunk), []}
  end
  defp take_while_fits([mod | rest], current_chunk, current_len) do
    # format: "  - #{inspect(mod)}\n"
    mod_str = "  - #{inspect(mod)}\n"
    mod_len = String.length(mod_str)

    base_len = if current_len == 0, do: 9, else: current_len

    if base_len + mod_len <= 1024 do
      take_while_fits(rest, [mod | current_chunk], base_len + mod_len)
    else
      {Enum.reverse(current_chunk), [mod | rest]}
    end
  end

  defp to_yaml(modules) do
    "modules:\n" <> Enum.map_join(modules, "", fn mod -> "  - #{inspect(mod)}\n" end)
  end
end
