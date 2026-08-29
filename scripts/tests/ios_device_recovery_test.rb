require "json"
require "minitest/autorun"
require "open3"
require "tempfile"

class IOSDeviceRecoveryTest < Minitest::Test
  SCRIPT = File.expand_path("../ios-device-recovery.sh", __dir__)

  def test_reports_connected_device_as_healthy
    status, output = run_helper("connected")

    assert status.success?
    assert_includes output, "Connection: connected"
    assert_includes output, "Retry the build/install"
  end

  def test_reports_connecting_device_as_stale
    status, output = run_helper("connecting")

    assert_equal 2, status.exitstatus
    assert_includes output, "stuck connecting"
    assert_includes output, "iOS: Clear Stale Pairing"
  end

  def test_clear_unpairs_and_repairs_stale_device
    command_log = Tempfile.new("devicectl-log")
    fake_devicectl = Tempfile.new("fake-devicectl")
    fake_devicectl.write("#!/bin/zsh\n" + 'print -r -- "$*" >> "$BRICKY_COMMAND_LOG"' + "\n")
    fake_devicectl.close
    File.chmod(0o755, fake_devicectl.path)

    status, output = run_helper(
      "connecting",
      "clear",
      "BRICKY_CONFIRM_UNPAIR" => "YES",
      "BRICKY_DEVICECTL" => fake_devicectl.path,
      "BRICKY_COMMAND_LOG" => command_log.path
    )

    assert status.success?
    assert_includes output, "Pairing refreshed"
    commands = File.read(command_log.path)
    assert_includes commands, "manage unpair --device C725091C-45EB-5E49-B112-3C980D58324D"
    assert_includes commands, "manage pair --device C725091C-45EB-5E49-B112-3C980D58324D"
  ensure
    command_log&.close!
    fake_devicectl&.unlink
  end

  def test_clear_refuses_to_unpair_connected_device
    status, output = run_helper("connected", "clear", "BRICKY_CONFIRM_UNPAIR" => "YES")

    assert_equal 3, status.exitstatus
    assert_includes output, "Refusing to clear a healthy connection"
  end

  private

  def run_helper(tunnel_state, action = "diagnose", environment = {})
    fixture = Tempfile.new(["devices", ".json"])
    fixture.write(JSON.generate(device_fixture(tunnel_state)))
    fixture.close

    Open3.capture2e(
      environment.merge("BRICKY_DEVICE_LIST_JSON" => fixture.path),
      "zsh",
      SCRIPT,
      action
    ).then { |output, status| [status, output] }
  ensure
    fixture&.unlink
  end

  def device_fixture(tunnel_state)
    {
      "result" => {
        "devices" => [
          {
            "identifier" => "C725091C-45EB-5E49-B112-3C980D58324D",
            "deviceProperties" => { "name" => "Ami’s iPhone" },
            "connectionProperties" => {
              "pairingState" => "paired",
              "tunnelState" => tunnel_state
            }
          }
        ]
      }
    }
  end
end