defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Monitors and generates SKILL.md documentation based on application modules.
  Runs continuously to keep documentation up-to-date according to standards.
  """
  use GenServer
  require Logger

  # 5 minutes interval for continuous processing
  @interval 5 * 60 * 1000
  # Limit the content size to adhere to documentation standards
  @char_limit 1024

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
    Logger.debug("Starting continuous SkillTracker documentation generation...")

    # Get modules of the application
    {:ok, modules} = :application.get_key(:governance_core, :modules)

    # Convert to strings and sort
    mod_strings =
      modules
      |> Enum.map(&to_string/1)
      |> Enum.sort()

    # Truncate source list before YAML formatting to prevent breaking YAML syntax
    truncated_mods = truncate_list(mod_strings, @char_limit, [])

    # Format as YAML Block Scalar
    yaml_content = generate_yaml(truncated_mods)

    # Write to project's source priv directory
    skill_path = Path.join([File.cwd!(), "governance_core", "priv", "SKILL.md"])

    # Ensure priv directory exists
    priv_dir = Path.dirname(skill_path)
    File.mkdir_p!(priv_dir)

    case File.write(skill_path, yaml_content) do
      :ok -> Logger.info("SKILL.md successfully updated at #{skill_path}")
      {:error, reason} -> Logger.error("Failed to write SKILL.md: #{inspect(reason)}")
    end
  end

  defp truncate_list([], _limit, acc), do: Enum.reverse(acc)
  defp truncate_list([item | rest], limit, acc) do
    # Calculate length if we add this item, approx 4 chars for list formatting
    current_len = calculate_yaml_length(acc)
    item_len = String.length(item) + 4

    if current_len + item_len <= limit do
      truncate_list(rest, limit, [item | acc])
    else
      Enum.reverse(acc)
    end
  end

  defp calculate_yaml_length(items) do
    header_len = String.length("---\nskills: |\n")
    items_len = Enum.reduce(items, 0, fn i, acc -> acc + String.length(i) + 4 end)
    footer_len = String.length("\n...\n")
    header_len + items_len + footer_len
  end

  defp generate_yaml(modules) do
    # Note: explicitly indent line-by-line for YAML block scalar string interpolation
    indented_mods =
      modules
      |> Enum.map(fn m -> "  - #{m}" end)
      |> Enum.join("\n")

    """
    ---
    skills: |
    #{indented_mods}
    ...
    """
  end
end
