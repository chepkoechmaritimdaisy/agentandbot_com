defmodule GovernanceCore.Monitoring do
  @moduledoc """
  The Monitoring context.
  """

  alias GovernanceCore.Monitoring.CommentMonitor

  def list_recent_comments do
    CommentMonitor.get_recent_comments()
  end

  def add_comment(attrs \ %{}) do
    # Simple map for now, could be a changeset later
    comment = %{
      id: System.unique_integer([:positive]),
      author: attrs["author"] || "Anonymous",
      content: attrs["content"] || "No content",
      source: attrs["source"] || "unknown",
      timestamp: DateTime.utc_now()
    }

    CommentMonitor.broadcast_comment(comment)
    {:ok, comment}
  end

  def subscribe do
    CommentMonitor.subscribe()
  end
end
