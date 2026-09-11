# DoltgreSQL 1.3.1: `UPDATE` reports how many rows it changed, not how many it matched

On DoltgreSQL 1.3.1, the command tag of an `UPDATE` counts only the rows whose values changed:
`UPDATE t SET a = a WHERE id = 1` matches one row and answers `UPDATE 0`. PostgreSQL 18.6 counts every row
the `UPDATE` matched, changed or not, and answers `UPDATE 1`; for an `UPDATE` that matches two rows and
changes one, PostgreSQL answers `UPDATE 2` and DoltgreSQL `UPDATE 1`.

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-update-row-count.git
cd repro-doltgresql-bug-update-row-count
./repro.sh
```

`repro.sh` starts PostgreSQL 18.6 and DoltgreSQL 1.3.1 in two throwaway containers, waits until both
accept connections, runs [`repro.sql`](repro.sql) on each with the `psql` client inside its container,
prints the two outputs side by side, and removes the containers. It exits 0 when DoltgreSQL's output is
identical to PostgreSQL's and 1 when it differs; with DoltgreSQL 1.3.1 it exits 1.

To try another DoltgreSQL release, name its image:

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory:

```sh
docker run -d --name repro-doltgresql-bug-update-row-count-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker run -d --name repro-doltgresql-bug-update-row-count-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql repro-doltgresql-bug-update-row-count-postgres:/tmp/repro.sql
docker cp repro.sql repro-doltgresql-bug-update-row-count-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-update-row-count-postgres psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-update-row-count-doltgresql psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-update-row-count-postgres repro-doltgresql-bug-update-row-count-doltgresql
```

If `docker exec` answers that the connection was refused, the server is still starting: wait a few
seconds and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
CREATE TABLE t (id int PRIMARY KEY, a int);
INSERT INTO t VALUES (1, 10), (2, 20);

-- Matches one row and leaves its value as it is.
UPDATE t SET a = a WHERE id = 1;

-- Matches both rows, but only row 2 gets a new value.
UPDATE t SET a = 10;

SELECT * FROM t ORDER BY id;
```

## Expected behavior

Each `UPDATE` reports the rows it matched: the first matches one row and changes nothing, the second
matches both rows and changes one. This is what PostgreSQL 18.6 does, from the first update on:

```
-- Matches one row and leaves its value as it is.
UPDATE t SET a = a WHERE id = 1;
UPDATE 1
-- Matches both rows, but only row 2 gets a new value.
UPDATE t SET a = 10;
UPDATE 2
SELECT * FROM t ORDER BY id;
 id | a  
----+----
  1 | 10
  2 | 10
(2 rows)
```

## Actual behavior

The table ends up the same, but each `UPDATE` reports only the rows whose values changed. This is what
DoltgreSQL 1.3.1 does, from the first update on:

```
-- Matches one row and leaves its value as it is.
UPDATE t SET a = a WHERE id = 1;
UPDATE 0
-- Matches both rows, but only row 2 gets a new value.
UPDATE t SET a = 10;
UPDATE 1
SELECT * FROM t ORDER BY id;
 id | a  
----+----
  1 | 10
  2 | 10
(2 rows)
```

## Side by side

The full output of `./repro.sh`:

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

CREATE TABLE t (id int PRIMARY KEY, a int);                   CREATE TABLE t (id int PRIMARY KEY, a int);
CREATE TABLE                                                  CREATE TABLE
INSERT INTO t VALUES (1, 10), (2, 20);                        INSERT INTO t VALUES (1, 10), (2, 20);
INSERT 0 2                                                    INSERT 0 2
-- Matches one row and leaves its value as it is.             -- Matches one row and leaves its value as it is.
UPDATE t SET a = a WHERE id = 1;                              UPDATE t SET a = a WHERE id = 1;
UPDATE 1                                                    | UPDATE 0
-- Matches both rows, but only row 2 gets a new value.        -- Matches both rows, but only row 2 gets a new value.
UPDATE t SET a = 10;                                          UPDATE t SET a = 10;
UPDATE 2                                                    | UPDATE 1
SELECT * FROM t ORDER BY id;                                  SELECT * FROM t ORDER BY id;
 id | a                                                        id | a  
----+----                                                     ----+----
  1 | 10                                                        1 | 10
  2 | 10                                                        2 | 10
(2 rows)                                                      (2 rows)


Result: DoltgreSQL's output differs from PostgreSQL's on 2 line(s), marked with |.
```

## Other observations

Each variant was run on DoltgreSQL 1.3.1 and on PostgreSQL 18.6, and PostgreSQL ran every one without
an error:

- An `UPDATE` that matches three rows and changes none answers `UPDATE 0` (PostgreSQL: `UPDATE 3`), and
  one that matches three rows and changes two answers `UPDATE 2` (PostgreSQL: `UPDATE 3`). An `UPDATE`
  that matches no row answers `UPDATE 0` on both.
- Setting a column to the literal value it already holds, a text column to the same text, or a NULL to
  NULL answers `UPDATE 0` (PostgreSQL: `UPDATE 1`).
- So does an `UPDATE` that changes nothing inside an explicit transaction, on a table without a primary
  key, or on a table with a `BEFORE UPDATE` trigger that returns `NEW`, and so does `SET id = id` on
  the primary key.
- An `UPDATE` sent through the extended query protocol with psql's `\bind`, setting a value the row
  already holds, answers `UPDATE 0` (PostgreSQL: `UPDATE 1`).
- With `RETURNING`, the count agrees with PostgreSQL: `UPDATE t SET a = a WHERE id = 1 RETURNING id, a`
  returns the row and answers `UPDATE 1` on both.
- In PL/pgSQL, `FOUND` follows the same count: a function that runs `UPDATE t SET a = a WHERE id = 1;`
  and then `RETURN FOUND;` returns `f` (PostgreSQL: `t`).
- `INSERT ... ON CONFLICT (id) DO UPDATE SET a = EXCLUDED.a` on an existing row answers `INSERT 0 0`
  when the row keeps its values and `INSERT 0 2` when it changes; PostgreSQL answers `INSERT 0 1` both
  times.
- The `UPDATE` count is also described in
  [dolthub/doltgresql#3113](https://github.com/dolthub/doltgresql/issues/3113).

## Environment

- DoltgreSQL 1.3.1, the newest release when this was written: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`. Its bundled `psql` is 18.6.
- Reproduced on 2026-09-10 with Docker 29.7.2 on Linux x86_64 (Ubuntu 26.04.1 LTS under WSL 2).
