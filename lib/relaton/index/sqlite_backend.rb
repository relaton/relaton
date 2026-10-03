# frozen_string_literal: true

require "sqlite3"

module Relaton
  module Index
    #
    # The SQLite materialization of one flavor index (relaton#242 phase 2).
    #
    # A downloaded index zip is built once into a local database whose rows
    # are `(number, sort_key, id_json, file)` with an index on `number` — the
    # narrowing key. A search materializes only its bucket; the whole index
    # is never resident. WAL journaling lets one build and concurrent readers
    # share the file across processes.
    #
    class SqliteBackend
      SCHEMA_VERSION = "1"

      def initialize(db_path, pubid_class: nil)
        @db_path = db_path
        @pubid_class = pubid_class
        @db = SQLite3::Database.new(db_path)
        @db.busy_timeout = 30_000
        @db.results_as_hash = false
        @db.execute("PRAGMA journal_mode=WAL")
        @db.execute("PRAGMA synchronous=NORMAL")
        create_schema
      end

      # Build from an enumerator of `[number, sort_key, id_hash, file]`
      # tuples. Callers hand the child process's enumerator here; the tuples
      # are written inside one transaction.
      def build(rows_enum)
        @db.transaction do
          @db.execute("DELETE FROM index_rows")
          @db.prepare("INSERT INTO index_rows (number, sort_key, id_json, file) VALUES (?, ?, ?, ?)") do |stmt|
            rows_enum.each { |(number, sort_key, id_hash, file)| stmt.execute(number, sort_key, JSON.generate(id_hash), file) }
          end
          meta_set("schema_version", SCHEMA_VERSION)
        end
      end

      # The bucket for a narrowing key: raw rows, ordered as written.
      def bucket(number)
        rows = []
        @db.execute("SELECT id_json, file FROM index_rows WHERE number = ? ORDER BY rowid", [number]) do |row|
          rows << { id: JSON.parse(row[0]), file: row[1] }
        end
        rows
      end

      def each_row
        @db.execute("SELECT id_json, file FROM index_rows ORDER BY rowid") do |row|
          yield({ id: JSON.parse(row[0]), file: row[1] })
        end
      end

      def count
        @db.get_first_value("SELECT COUNT(*) FROM index_rows").to_i
      end

      def stale_schema?
        meta_get("schema_version") != SCHEMA_VERSION
      end

      def close
        @db.close
      end

      private

      def create_schema
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS index_rows (
            number TEXT NOT NULL,
            sort_key TEXT NOT NULL,
            id_json TEXT NOT NULL,
            file TEXT NOT NULL
          )
        SQL
        @db.execute("CREATE INDEX IF NOT EXISTS idx_index_rows_number ON index_rows (number)")
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS index_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        SQL
      end

      def meta_set(key, value)
        @db.execute("INSERT OR REPLACE INTO index_meta (key, value) VALUES (?, ?)", [key, value])
      end

      def meta_get(key)
        @db.get_first_value("SELECT value FROM index_meta WHERE key = ?", [key])
      end
    end
  end
end
