use std::{env, fs, process::Command};
use asky::MultiSelect;

struct Selections {
    statuses: Vec<String>,
    machines: Vec<String>,
}

fn request_selection() -> Selections {
    let status_options = vec!["battery", "updates", "critical services"];
    let status_prompt = "hey! what would you like to check?";
    let machine_prompt = "okay, and which machines?";

    let home = env::var("HOME").expect("couldn't find HOME env var");
    let ssh_config_file = format!("{home}/.ssh/config");

    let status_answer = MultiSelect::new(status_prompt, status_options)
        .prompt()
        .expect("couldn't get status selection :(");

    let machine_list: Vec<String> = fs::read_to_string(&ssh_config_file)
        .expect("couldn't read SSH config file")
        .lines()
        .filter(|line| line.trim_start().starts_with("Host "))
        .map(|line| line.trim_start()[5..].trim().to_string())
        .collect();

    // asky needs &str items, so borrow from machine_list rather than moving it
    let machine_refs: Vec<&str> = machine_list.iter().map(|s| s.as_str()).collect();
    let machine_answer = MultiSelect::new(machine_prompt, machine_refs)
        .prompt()
        .expect("couldn't get machines :/");

    Selections {
        statuses: status_answer.into_iter().map(String::from).collect(),
        machines: machine_answer.into_iter().map(String::from).collect(),
    }
}

fn check_battery(machines: &[String]) -> Vec<(String, Result<String, String>)> {
    machines
        .iter()
        .map(|machine| {
            let outcome = match Command::new("ssh")
                .arg(machine)
                .arg("upower")
                .arg("-i")
                .arg("/org/freedesktop/UPower/devices/DisplayDevice")
                .output()
            {
                Ok(output) if output.status.success() => {
                    Ok(String::from_utf8_lossy(&output.stdout).to_string())
                }
                Ok(output) => Err(String::from_utf8_lossy(&output.stderr).to_string()),
                Err(e) => Err(format!("failed to run ssh: {e}")),
            };
            (machine.clone(), outcome)
        })
        .collect()
}

fn display_battery_results(results: &[(String, Result<String, String>)]) {
    for (machine, outcome) in results {
        match outcome {
            Ok(stdout) => println!("[{machine}] battery:\n{stdout}"),
            Err(stderr) => eprintln!("[{machine}] couldn't get battery status:\n{stderr}"),
        }
    }
}

fn main() {
    let selections = request_selection();

    if selections.statuses.iter().any(|s| s == "battery") {
        let results = check_battery(&selections.machines);
        display_battery_results(&results);
    }
}
