import Demo.Factory

category_names = ["Tech", "Misc", "Crew", "News"]

categories =
  Enum.reduce(category_names, [], fn name, acc ->
    [insert(:category, name: name) | acc]
  end)

tag_names = ["DIY", "expert", "beginner"]

tags = Enum.map(tag_names, &insert(:tag, name: &1))

admin_user = insert(:user, role: :admin)
users = [admin_user | insert_list(9, :user)]

for _index <- 0..50 do
  insert(:post, category: Enum.random(categories), tags: [Enum.random(tags)], user: Enum.random(users))
end

insert_list(10, :product)

insert_list(10, :address)

:code.priv_dir(:demo)
|> Path.join("repo/film_reviews.csv")
|> File.stream!()
|> Stream.drop(1)
|> CSV.decode(
  headers: [
    :title,
    :overview
  ],
  escape_max_lines: 20
)
|> Enum.each(fn {:ok, item} ->
  Demo.FilmReview.create_changeset(%Demo.FilmReview{}, item)
  |> Demo.Repo.insert!()
end)

insert_list(10, :ticket)
