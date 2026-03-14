defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Standardizes and updates SKILL.md for tools and skills.
  Ensures 1024 character limit and YAML frontmatter.
  """
  use GenServer
  require Logger

  @file_path "SKILL.md"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  @doc """
  Appends a new skill to the SKILL.md file.
  """
  def append_skill(name, description) do
    GenServer.cast(__MODULE__, {:append, name, description})
  end

  def handle_cast({:append, name, description}, state) do
    entry = format_entry(name, description)
    case File.write(@file_path, entry, [:append]) do
      :ok -> Logger.info("Appended skill #{name} to SKILL.md")
      {:error, reason} -> Logger.error("Failed to write to SKILL.md: #{inspect(reason)}")
    end
    {:noreply, state}
  end

  defp format_entry(name, description) do
    # Ensure description isn't too long. Frontmatter + name + description should be <= 1024
    frontmatter = """
    ---
    name: #{name}
    ---
    """

    # Calculate how much space we have for the description
    available_space = 1024 - String.length(frontmatter) - 1 # -1 for newline

    truncated_description = String.slice(description, 0, max(0, available_space))

    """
    #{frontmatter}#{truncated_description}
    """
  end
end
