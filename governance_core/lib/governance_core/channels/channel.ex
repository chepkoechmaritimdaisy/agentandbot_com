defmodule GovernanceCore.Channels.Channel do
  @moduledoc """
  Behavior for a pluggable communication channel in the swarm.
  Channels can be Telegram, Discord, Email, or Markdown files.
  """

  @doc """
  Delivers a message or task payload to the agent via the specific channel.
  Returns :ok if successful, or {:error, reason} if not.
  """
  @callback deliver(agent_id :: binary(), payload :: map()) :: :ok | {:error, any()}

  @doc """
  Checks if the channel is currently 'healthy' or available for use.
  Used for automated fallback logic.
  """
  @callback status() :: :online | :offline | :upgrading
end
