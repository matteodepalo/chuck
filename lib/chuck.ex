defmodule Chuck do
  defmodule ReviewBot do
    use Marvin.Bot

    match {:direct, ~r/review/}

    def handle_message(message, slack) do
      review_candidates = Enum.filter(channel_members(message, slack), fn (id) ->
        !Map.get(slack.users[id], :is_bot, false) && id != message.user
      end)

      if Enum.count(review_candidates) > 0 do
        reviewer = Enum.random(review_candidates)
        send_message("<@#{reviewer}> kindly review that PR.", message.channel, slack)
      else
        send_message("No reviewers available.", message.channel, slack)
      end
    end

    defp channel_members(message, slack) do
      if Enum.member?(Map.keys(slack.groups), message.channel) do
        {:ok, %HTTPoison.Response{ body: body }} = Marvin.WebAPI.api("/groups.info", [channel: message.channel])
        body["group"]["members"]
      else
        {:ok, %HTTPoison.Response{ body: body }} = Marvin.WebAPI.api("/channels.info", [channel: message.channel])
        body["channel"]["members"]
      end
    end
  end
end
