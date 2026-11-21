# Test Scripts for Manual Acceptance

These small shell scripts verify ScriptDeck's core behaviors without touching external services or deleting files.

| Script | Purpose | Expected ScriptDeck Behavior |
| --- | --- | --- |
| `continuous_worker.sh` | Runs continuously until `SIGTERM` | Stays `Running`, increments `HH:MM:SS`, stops cleanly to `Stopped` on `Stop` |
| `quick_success.sh` | Sleeps 2s then exits `0` | Transitions `Running` → `Stopped`, preserves `00:00:02` duration |
| `fail_exit.sh` | Sleeps 1s then exits `42` | Transitions `Running` → `Failed` with `Exit code 42` |
| `parent_with_child.sh` | Spawns `/bin/sleep 300 &` in foreground group and waits | Clicking `Stop` terminates both the shell and child `sleep` process |
| `noisy_output.sh` | Continuously writes heavy `stdout` and `stderr` | Discarded via `/dev/null`; ScriptDeck memory stays flat and UI stays responsive |

## Example Configuration

- **Name**: `Continuous Worker`
- **Directory**: `/Users/<you>/Documents/project/script-deck/test-scripts`
- **Command**: `./continuous_worker.sh`
