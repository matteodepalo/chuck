defmodule Chuck do
  defmodule ReviewBot do
    use Marvin.Bot

    match {:direct, ~r/review/}

    def handle_message(message, slack) do
      {:ok, redis_client} = Exredis.start_link

      all_reviewers = reviewers(slack, redis_client)
      review_candidates = possible_reviewers(all_reviewers, message, slack)

      if Enum.count(Map.keys(review_candidates)) > 0 do
        lowest_count = Enum.min(Map.values(review_candidates))

        reviewer = review_candidates
        |> Enum.filter(fn ({ _id, count }) -> count == lowest_count end)
        |> Enum.into(%{})
        |> Map.keys
        |> Enum.random

        updated_reviewers = Dict.put(all_reviewers, reviewer, all_reviewers[reviewer] + 1)
        Exredis.Api.set(redis_client, "reviewers", Poison.encode!(updated_reviewers))
        send_message("<@#{reviewer}> kindly review that PR.", message.channel, slack)
      else
        send_message("No reviewers available.", message.channel, slack)
      end

      Exredis.stop(redis_client)
    end

    defp reviewers(slack, redis_client) do
      case Exredis.Api.get(redis_client, "reviewers") do
        :undefined ->
          reviewers = Map.keys(slack.users)
          |> Enum.reduce(%{}, fn (reviewer, acc) -> Dict.put(acc, reviewer, 0) end)
          Exredis.Api.set(redis_client, "reviewers", Poison.encode!(reviewers))
          reviewers
        reviewers -> Poison.decode!(reviewers)
      end
    end

    def possible_reviewers(reviewers, message, slack) do
      channel_reviewers = channel_members(message, slack)

      reviewers
      |> Enum.filter(fn ({ id, _count }) ->
        Enum.member?(channel_reviewers, id) &&
        Map.get(slack.users[id], :presence) == "active" &&
        !Map.get(slack.users[id], :is_bot, false) &&
        Map.get(slack.users[id], :name) != "slackbot" &&
        id != message.user
      end)
      |> Enum.into(%{})
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
