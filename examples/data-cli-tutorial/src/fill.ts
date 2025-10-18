import { readFile } from "node:fs/promises";
import { parse } from "csv-parse/sync";

import { initClient } from "trailbase";
import type { Movie } from "@schema/movie";

const client = initClient("http://localhost:4000");
await client.login("admin@localhost", "secret");
const api = client.records<Movie>("movies");

// Start fresh: delete all existing movies.
let cnt = 0;
while (true) {
  const movies = await api.list({
    pagination: {
      limit: 100,
    },
  });

  const records = movies.records;
  const length = records.length;
  if (length === 0) {
    break;
  }
  cnt += length;

  for (const movie of records) {
    await api.delete(movie.rank!);
  }
}

console.log(`Cleaned up ${cnt} movies`);

const file = await readFile("data/Top_1000_IMDb_movies_New_version.csv");
const records = parse(file, {
  fromLine: 2,
  // prettier-ignore
  columns: ["rank", "name", "year", "watch_time", "rating", "metascore", "gross", "votes", "description"],
});

for (const movie of records) {
  const record: Movie = {
    rank: parseInt(movie.rank),
    name: movie.name,
    year: movie.year,
    watch_time: parseInt(movie.watch_time),
    rating: parseFloat(movie.rating),
    metascore: movie.metascore,
    gross: movie.gross,
    votes: movie.votes,
    description: movie.description,
  };

  await api.create(record);
}

console.log(`Inserted ${records.length} movies`);
