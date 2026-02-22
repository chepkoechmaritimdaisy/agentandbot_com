defmodule GovernanceCore.Protocols.UMP do
  @moduledoc """
  Parses the Universal Message Protocol (UMP) payload carried within ClawSpeak frames.
  Currently supports JSON payloads.
  """

  @doc """
  Parses the payload into a structured map.
  """
  def parse(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, :invalid_json}
    end
  end
end
