defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that dynamically tracks tools/modules in the system
  and automatically generates `SKILL.md` files conforming to the universal standard
  (YAML format, 1024 character limit per file).
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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

  defp perform_update do
    Logger.info("Updating SKILL.md...")

    modules = case :application.get_key(:governance_core, :modules) do
      {:ok, mods} -> mods
      _ -> []
    end

    # Filter out a few interesting ones or just use all
    tools = modules
    |> Enum.map(fn m ->
      %{
        "name" => to_string(m),
        "description" => "Module in GovernanceCore",
        "type" => "module"
      }
    end)

    generate_skill_files(tools)
    Logger.info("SKILL.md updating complete.")
  end

  defp generate_skill_files(tools) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    chunks = chunk_by_length(tools, 1024)

    Enum.with_index(chunks)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      filepath = Path.join(priv_dir, filename)

      yaml_content = generate_yaml(chunk)

      case File.write(filepath, yaml_content) do
        :ok -> Logger.info("Written #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp chunk_by_length(items, max_len) do
    Enum.reduce(items, [[]], fn item, [current_chunk | rest] = acc ->
      current_yaml = generate_yaml(current_chunk ++ [item])

      if String.length(current_yaml) > max_len do
        if current_chunk == [] do
          # Single item exceeds max length, have to put it in anyway
          [[item] | acc]
        else
          [[item], current_chunk | rest]
        end
      else
        [current_chunk ++ [item] | rest]
      end
    end)
    |> Enum.reverse()
    |> Enum.reject(&(&1 == []))
  end

  defp generate_yaml(items) do
    # Simple YAML generation
    items_str = items
    |> Enum.map(fn item ->
      """
      - name: #{item["name"]}
        description: #{item["description"]}
        type: #{item["type"]}
      """
    end)
    |> Enum.join("")

    "tools:\n" <> items_str
  end
end
