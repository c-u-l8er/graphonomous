defmodule Graphonomous.FilesystemTraversalTest do
  use ExUnit.Case, async: false

  alias Graphonomous.FilesystemTraversal

  describe "scan_directory/2" do
    test "recursively scans files and applies extension/hidden filters" do
      root = make_tmp_dir!("scan-filters")

      File.write!(Path.join(root, "a.txt"), "alpha")
      File.write!(Path.join(root, ".hidden.txt"), "hidden")

      sub = Path.join(root, "sub")
      File.mkdir_p!(sub)
      File.write!(Path.join(sub, "b.md"), "bravo")
      File.write!(Path.join(sub, "c.ex"), "charlie")

      parent = self()

      ingest_fun = fn event ->
        send(parent, {:ingested, event})
        :ok
      end

      assert {:ok, result} =
               FilesystemTraversal.scan_directory(root,
                 recursive: true,
                 include_hidden: false,
                 extensions: [".txt", ".md"],
                 ingest_fun: ingest_fun
               )

      assert result.root_path == Path.expand(root)
      assert result.files_discovered == 2
      assert result.files_ingested == 2
      assert result.files_failed == 0
      assert result.errors == []

      assert_receive {:ingested, %{type: :added, relative_path: "a.txt"}}, 1_000
      assert_receive {:ingested, %{type: :added, relative_path: "sub/b.md"}}, 1_000
      refute_receive {:ingested, %{relative_path: ".hidden.txt"}}, 200
      refute_receive {:ingested, %{relative_path: "sub/c.ex"}}, 200
    end

    test ".gitignore is ignored even when include_hidden is true" do
      root = make_tmp_dir!("scan-gitignore")

      File.write!(Path.join(root, ".gitignore"), "*.beam\n")
      File.write!(Path.join(root, ".hidden.txt"), "hidden")
      File.write!(Path.join(root, "visible.txt"), "visible")

      parent = self()

      ingest_fun = fn event ->
        send(parent, {:ingested_path, event.relative_path})
        :ok
      end

      assert {:ok, result} =
               FilesystemTraversal.scan_directory(root,
                 include_hidden: true,
                 ingest_fun: ingest_fun
               )

      assert result.files_discovered == 2
      assert result.files_ingested == 2
      assert result.files_failed == 0

      assert_receive {:ingested_path, ".hidden.txt"}, 1_000
      assert_receive {:ingested_path, "visible.txt"}, 1_000
      refute_receive {:ingested_path, ".gitignore"}, 200
    end

    test ".gitignore patterns exclude matching files and directories from traversal" do
      root = make_tmp_dir!("scan-gitignore-patterns")

      File.write!(
        Path.join(root, ".gitignore"),
        """
        ignored_dir/
        *.log
        !important.log
        nested/*.tmp
        """
      )

      File.write!(Path.join(root, "kept.txt"), "keep")
      File.write!(Path.join(root, "ignored.log"), "ignore")
      File.write!(Path.join(root, "important.log"), "keep-negated")

      ignored_dir = Path.join(root, "ignored_dir")
      File.mkdir_p!(ignored_dir)
      File.write!(Path.join(ignored_dir, "inside.txt"), "ignore-dir")

      nested = Path.join(root, "nested")
      File.mkdir_p!(nested)
      File.write!(Path.join(nested, "temp.tmp"), "ignore-tmp")
      File.write!(Path.join(nested, "keep.txt"), "keep-nested")

      parent = self()

      ingest_fun = fn event ->
        send(parent, {:ingested_path, event.relative_path})
        :ok
      end

      assert {:ok, result} =
               FilesystemTraversal.scan_directory(root,
                 include_hidden: true,
                 ingest_fun: ingest_fun
               )

      assert result.files_discovered == 3
      assert result.files_ingested == 3
      assert result.files_failed == 0

      assert_receive {:ingested_path, "kept.txt"}, 1_000
      assert_receive {:ingested_path, "important.log"}, 1_000
      assert_receive {:ingested_path, "nested/keep.txt"}, 1_000

      refute_receive {:ingested_path, "ignored.log"}, 200
      refute_receive {:ingested_path, "ignored_dir/inside.txt"}, 200
      refute_receive {:ingested_path, "nested/temp.tmp"}, 200
    end

    test "tracks failed ingestions in summary output" do
      root = make_tmp_dir!("scan-failures")
      ok_file = Path.join(root, "ok.txt")
      bad_file = Path.join(root, "bad.txt")

      File.write!(ok_file, "ok")
      File.write!(bad_file, "bad")

      ingest_fun = fn event ->
        if event.relative_path == "bad.txt", do: {:error, :boom}, else: :ok
      end

      assert {:ok, result} =
               FilesystemTraversal.scan_directory(root,
                 extensions: [".txt"],
                 ingest_fun: ingest_fun
               )

      assert result.files_discovered == 2
      assert result.files_ingested == 1
      assert result.files_failed == 1
      assert length(result.errors) == 1
      assert hd(result.errors).path |> String.ends_with?("bad.txt")
    end
  end

  describe "watch_directory lifecycle" do
    test "start_watch/2 detects add, modify, and remove events and stops cleanly" do
      root = make_tmp_dir!("watch-events")
      watched = Path.join(root, "live.txt")

      parent = self()

      ingest_fun = fn event ->
        send(parent, {:watch_event, event.type, event.relative_path})
        :ok
      end

      assert {:ok, pid} =
               FilesystemTraversal.start_watch(root,
                 poll_interval_ms: 50,
                 ingest_on_start: false,
                 extensions: [".txt"],
                 ingest_fun: ingest_fun
               )

      File.write!(watched, "v1")
      assert_receive {:watch_event, :added, "live.txt"}, 2_000

      File.write!(watched, "v2")
      assert_receive {:watch_event, :modified, "live.txt"}, 2_000

      File.rm!(watched)
      assert_receive {:watch_event, :removed, "live.txt"}, 2_000

      assert :ok = FilesystemTraversal.stop_watch(pid)

      assert_receive {:filesystem_watch_exit, ^pid, {:stopped, stats}}, 2_000
      assert stats.events_seen >= 3
      assert stats.ingested >= 3
    end

    test "watch_directory/2 ingests existing files on startup when enabled" do
      root = make_tmp_dir!("watch-startup")
      File.write!(Path.join(root, "seed.txt"), "seed")

      parent = self()

      ingest_fun = fn event ->
        send(parent, {:startup_event, event.type, event.relative_path})
        :ok
      end

      assert {:ok, pid} =
               FilesystemTraversal.start_watch(root,
                 poll_interval_ms: 50,
                 ingest_on_start: true,
                 extensions: [".txt"],
                 ingest_fun: ingest_fun
               )

      assert_receive {:startup_event, :added, "seed.txt"}, 2_000

      assert :ok = FilesystemTraversal.stop_watch(pid)
      assert_receive {:filesystem_watch_exit, ^pid, {:stopped, _stats}}, 2_000
    end
  end

  defp make_tmp_dir!(prefix) do
    unique = System.unique_integer([:positive, :monotonic])
    path = Path.join(System.tmp_dir!(), "graphonomous-#{prefix}-#{unique}")
    File.mkdir_p!(path)

    on_exit(fn ->
      File.rm_rf(path)
    end)

    path
  end
end
