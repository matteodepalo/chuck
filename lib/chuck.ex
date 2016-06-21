defmodule Chuck do
  defmodule ReviewBot do
    use Marvin.Bot

    match {:direct, ~r/review/}

    def handle_message(message, slack) do
      {:ok, redis_client} = Exredis.start_link

      reviewer_to_exclude = last_reviewer(redis_client, message)
      review_candidates = possible_reviewers(reviewer_to_exclude, message, slack)

      if Enum.count(review_candidates) > 0 do
        reviewer = pick_at_random(review_candidates)
        Exredis.Api.set(redis_client, "#{message.channel}_last_reviewer", reviewer)
        send_message("<@#{reviewer}> kindly review that PR.", message.channel, slack)
      else
        send_message("No reviewers available.", message.channel, slack)
      end

      Exredis.stop(redis_client)
    end

    defp last_reviewer(redis_client, message) do
      case Exredis.Api.get(redis_client, "#{message.channel}_last_reviewer") do
        :undefined -> nil
        reviewer -> reviewer
      end
    end

    defp possible_reviewers(reviewer_to_exclude, message, slack) do
      channel_members(message, slack)
      |> Enum.filter(fn (id) ->
        Map.get(slack.users[id], :presence) == "active" &&
        !Map.get(slack.users[id], :is_bot, false) &&
        Map.get(slack.users[id], :name) != "slackbot" &&
        id != reviewer_to_exclude &&
        id != message.user
      end)
    end

    defp pick_at_random(reviewers) do
      Enum.random(reviewers)
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
