#!/home/alt/scripts/.builder_venv/bin/python3
import subprocess as sp
import questionary as q


def list_machines():
    print("Hi! \nLet's have some fun! Here's your machines:")
    cmd = "virsh --connect qemu:///system list --all --name".split()
    out = sp.run(cmd, capture_output=True, text=True, check=True)
    machines = [m for m in out.stdout.splitlines() if m.strip()]
    print("\n".join(machines))
    return machines


def choose_options(machines):
    choice_1 = q.select(
        "which box are you messing with?",
        choices=machines,
    ).ask()
    actions = ["on", "off"]
    choice_2 = q.select(
        "Turning it on or off?",
        choices=actions,
    ).ask()
    options = [choice_1, choice_2]
    print(options)
    return options


def run(options):
    name = options[0]
    if options[1] == "on":
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
    elif options[1] == "off":
        print(f"well geeze, fine - I'll kill: {name}")
        stop = "virsh --connect qemu:///system shutdown".split()
        sp.run(stop + [name], check=True)
    else:
        pass


def main():
    machines = list_machines()
    options = choose_options(machines)
    run(options)


if __name__ == "__main__":
    main()
