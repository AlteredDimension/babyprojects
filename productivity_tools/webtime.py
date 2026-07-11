#!/home/alt/scripts/.builder_venv/bin/python3
import subprocess as sp
import questionary as q


def list_machines():
    print("Hi! \nLet's have some fun! Here's your machines:\n")
    cmd = "virsh --connect qemu:///system list --all".split()
    out = sp.run(cmd, capture_output=True, text=True, check=True)

    machines = {}
    for line in out.stdout.splitlines()[2:]:  # skip the header rows
        if not line.strip():
            continue
        machine_id, name, state = line.split(maxsplit=2)
        machines[name] = {"id": machine_id, "state": state}
    return machines


def choose_options(machines):
    name = q.select(
        "which box are you messing with?",
        choices=list(machines),
    ).ask()
    action = q.select(
        "Turning it on or off?",
        choices=["on", "off"],
    ).ask()
    return [name, action]


def run(options, machines):
    name, action = options
    state = machines[name]["state"]

    if action == "on":
        if state == "running":
            print(f"{name} is already running — attaching viewer...")
            viewer = "virt-viewer --connect qemu:///system --attach".split()
            sp.Popen(
                viewer + [name],
                start_new_session=True,
                stdin=sp.DEVNULL,
                stdout=sp.DEVNULL,
                stderr=sp.DEVNULL,
            )
            print(f"viewer attached to {name} — you can close this terminal.")
            return

        print(f"okay!! running: {name}...")
        start = "virsh --connect qemu:///system start".split()
        sp.run(start + [name], check=True)
        viewer = "virt-viewer --connect qemu:///system".split()
        sp.Popen(
            viewer + [name],
            start_new_session=True,
            stdin=sp.DEVNULL,
            stdout=sp.DEVNULL,
            stderr=sp.DEVNULL,
        )
        print(f"viewer launched for {name} — you can close this terminal.")

    elif action == "off":
        print(f"well geeze, fine - I'll kill: {name}")
        stop = "virsh --connect qemu:///system shutdown".split()
        sp.run(stop + [name], check=True)


def main():
    machines = list_machines()
    options = choose_options(machines)
    run(options, machines)


if __name__ == "__main__":
    main()
