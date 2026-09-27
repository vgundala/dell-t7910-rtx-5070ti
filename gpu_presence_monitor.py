#!/usr/bin/env python3
"""
RTX 5070 Ti Physical Seating & Presence Monitor Daemon
Monitors Slot 4 (PCIe Root Port 00:03.0) Presence Detect State (Pin B81 / PRSNT).

Requirements:
- If the card end pins lift or lose contact:
    Displays a single PERSISTENT desktop notification until fixed or dismissed.
    Does NOT repeatedly push notifications while staying in the unseated state.
- When state changes from unseated to seated:
    Automatically closes the unseated notification.
    Pushes a single confirmation notification that contact is restored.
    Triggers initialization if the GPU is not yet active.
"""

import os
import sys
import time
import glob
import subprocess
import pwd

PORT = "00:03.0"
SYSFS_DEVICE = "/sys/bus/pci/devices/0000:00:03.0"
CHECK_INTERVAL_SECONDS = 2


def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def get_active_desktop_users():
    """Finds all logged-in desktop users with an active D-Bus session socket."""
    users = []
    for bus_path in sorted(glob.glob("/run/user/*/bus")):
        try:
            uid = int(bus_path.split("/")[3])
            if uid >= 1000:
                pw = pwd.getpwuid(uid)
                users.append((pw.pw_name, uid, bus_path))
        except Exception:
            continue
    return users


def send_user_notification(username, uid, bus_path, summary, body, urgency=2, timeout=0, replace_id=0):
    """Dispatches a notification into the user's desktop session via D-Bus."""
    script = f"""
import dbus, sys
try:
    bus = dbus.bus.BusConnection("unix:path={bus_path}")
    obj = bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
    iface = dbus.Interface(obj, "org.freedesktop.Notifications")
    hints = {{"urgency": dbus.Byte({urgency}), "resident": dbus.Boolean(True)}}
    nid = iface.Notify(
        "RTX 5070 Ti Monitor",
        dbus.UInt32({replace_id}),
        "",
        {repr(summary)},
        {repr(body)},
        [],
        hints,
        dbus.Int32({timeout})
    )
    print(nid)
except Exception as e:
    sys.exit(1)
"""
    cmd = [sys.executable, "-c", script]
    try:
        if os.getuid() == 0:
            res = subprocess.run(["runuser", "-u", username, "--"] + cmd, capture_output=True, text=True, timeout=5)
        else:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        out = res.stdout.strip()
        if out.isdigit():
            return int(out)
    except Exception as e:
        log(f"Error dispatching notification to {username}: {e}")
    return 0


def close_user_notification(username, uid, bus_path, nid):
    """Closes an active notification on the user's desktop."""
    if not nid or nid <= 0:
        return
    script = f"""
import dbus
try:
    bus = dbus.bus.BusConnection("unix:path={bus_path}")
    obj = bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
    iface = dbus.Interface(obj, "org.freedesktop.Notifications")
    iface.CloseNotification(dbus.UInt32({nid}))
except Exception:
    pass
"""
    cmd = [sys.executable, "-c", script]
    try:
        if os.getuid() == 0:
            subprocess.run(["runuser", "-u", username, "--"] + cmd, capture_output=True, timeout=5)
        else:
            subprocess.run(cmd, capture_output=True, timeout=5)
    except Exception:
        pass


class GPUPresenceMonitor:
    def __init__(self):
        self.current_state = None  # True = Seated/Connected, False = Unseated/Disconnected
        self.unseated_notification_id = 0
        self.user_dismissed = False

    def check_presence(self):
        """
        Queries hardware Presence Detect State on PCIe Port 00:03.0.
        Returns:
            True if card is physically detected/seated (Pin B81 grounded or link trained).
            False if card is unseated / pins lifted.
        """
        # 1. Check if link width > 0 (if link is up, card is 100% physically present)
        try:
            with open(f"{SYSFS_DEVICE}/current_link_width", "r") as f:
                width = int(f.read().strip())
                if width > 0:
                    return True
        except Exception:
            pass

        # 2. Query hardware Slot Status register (CAP_EXP+1a.w) via setpci
        try:
            res = subprocess.run(
                ["/usr/bin/setpci", "-s", PORT, "CAP_EXP+1a.w"],
                capture_output=True,
                text=True,
                timeout=2
            )
            out = res.stdout.strip()
            if out:
                val = int(out, 16)
                pds = (val >> 6) & 1  # Bit 6 is Presence Detect State
                return bool(pds)
        except Exception:
            pass

        return False

    def notify_unseated(self):
        """Displays a persistent notification that the card has lifted/unseated."""
        users = get_active_desktop_users()
        if not users:
            log("No active desktop user found to notify.")
            return

        summary = "RTX 5070 Ti: Hardware Pin Disconnected"
        body = (
            "The rear pins of your RTX 5070 Ti in Slot 4 have lifted or lost electrical contact.\n"
            "Please press down firmly on the rear of the card until the retention clip clicks."
        )

        for username, uid, bus_path in users:
            nid = send_user_notification(
                username, uid, bus_path,
                summary, body,
                urgency=2, timeout=0,
                replace_id=self.unseated_notification_id
            )
            if nid > 0:
                self.unseated_notification_id = nid
                log(f"Posted unseated alert to {username} (Notification ID: {nid})")

    def notify_seated(self):
        """Notifies user that electrical contact has been restored, and closes error alert."""
        users = get_active_desktop_users()
        if not users:
            return

        # Close unseated alert
        if self.unseated_notification_id > 0:
            for username, uid, bus_path in users:
                close_user_notification(username, uid, bus_path, self.unseated_notification_id)
            log(f"Closed unseated alert (Notification ID: {self.unseated_notification_id})")
            self.unseated_notification_id = 0

        summary = "RTX 5070 Ti: Electrical Contact Restored"
        body = "The card pins in Slot 4 are seated and electrical contact is confirmed."

        for username, uid, bus_path in users:
            send_user_notification(
                username, uid, bus_path,
                summary, body,
                urgency=1, timeout=6000,
                replace_id=0
            )
            log(f"Posted seated confirmation to {username}")

    def trigger_auto_init(self):
        """Automatically runs initialization if the driver is not yet active."""
        try:
            res = subprocess.run(["nvidia-smi"], capture_output=True, timeout=3)
            if res.returncode != 0:
                log("Card seated but driver inactive. Triggering initialization script...")
                init_script = "/usr/local/bin/init_gpu_boot.sh"
                if not os.path.isfile(init_script):
                    init_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "init_gpu_boot.sh")
                if os.path.isfile(init_script):
                    subprocess.Popen([init_script])
            else:
                log("NVIDIA driver is already active.")
        except Exception as e:
            log(f"Error checking driver: {e}")

    def poll(self):
        """Periodic check executed every CHECK_INTERVAL_SECONDS."""
        is_present = self.check_presence()

        # State transition: Newly unseated
        if self.current_state is True and not is_present:
            log("STATE CHANGE: GPU unseated / Pin B81 disconnected!")
            self.current_state = False
            self.notify_unseated()

        # State transition: Newly seated / contact restored
        elif self.current_state is False and is_present:
            log("STATE CHANGE: GPU seated / electrical contact restored!")
            self.current_state = True
            self.notify_seated()
            self.trigger_auto_init()

        # First run initialization
        elif self.current_state is None:
            self.current_state = is_present
            log(f"Initial monitor state: {'SEATED' if is_present else 'UNSEATED'}")
            if not is_present:
                self.notify_unseated()

        # Re-attempt notification if previously unseated but no desktop was active at boot
        elif not is_present and self.unseated_notification_id == 0:
            self.notify_unseated()

    def run(self):
        log("RTX 5070 Ti Presence Monitor started.")
        while True:
            try:
                self.poll()
            except Exception as e:
                log(f"Error in poll loop: {e}")
            time.sleep(CHECK_INTERVAL_SECONDS)


if __name__ == "__main__":
    monitor = GPUPresenceMonitor()
    monitor.run()
