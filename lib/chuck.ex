defmodule Chuck do
  defmodule ReviewBot do
    use Marvin.Bot

    match {:direct, ~r/review/}

    def handle_message(message, slack) do
      {:ok, redis_client} = Exredis.start_link

      stored_reviewers = reviewers(message, slack, redis_client)
      review_candidates = stored_reviewers
      |> Enum.filter(fn ({ id, _count }) ->
        !Map.get(slack.users[id], :is_bot, false) && Map.get(slack.users[id], :presence, "active") && id != message.user
      end)
      |> Enum.into(%{})

      if Enum.count(Map.keys(review_candidates)) > 0 do
        lowest_count = Enum.min(Map.values(review_candidates))

        reviewer = review_candidates
        |> Enum.filter(fn ({ _id, count }) -> count == lowest_count end)
        |> Enum.into(%{})
        |> Map.keys
        |> Enum.random

        updated_reviewers = Dict.put(stored_reviewers, reviewer, stored_reviewers[reviewer] + 1)
        Exredis.Api.set(redis_client, "reviewers", Poison.encode!(updated_reviewers))
        send_message("<@#{reviewer}> kindly review that PR.", message.channel, slack)
      else
        send_message("No reviewers available.", message.channel, slack)
      end

      Exredis.stop(redis_client)
    end

    defp reviewers(message, slack, redis_client) do
      case Exredis.Api.get(redis_client, "reviewers") do
        :undefined ->
          reviewers = channel_members(message, slack)
          |> Enum.reduce(%{}, fn (reviewer, acc) -> Dict.put(acc, reviewer, 0) end)
          Exredis.Api.set(redis_client, "reviewers", Poison.encode!(reviewers))
          reviewers
        reviewers -> Poison.decode!(reviewers)
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
