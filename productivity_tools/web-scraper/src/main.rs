use reqwest::blocking::get;
use scraper::{Html, Selector};
use csv::Writer;
use std::error::Error;

fn main() -> Result<(), Box<dyn Error>> {
    let url = "https://www.maxpreps.com/sc/fort-mill/fort-mill-yellow-jackets/basketball/schedule/";
    let body = get(url)?.text()?;
    let document = Html::parse_document(&body);

    let row_selector = Selector::parse("tr")?;
    let cell_selector = Selector::parse("td")?;

    // Google Calendar CSV headers
    let mut wtr = Writer::from_path("fort_mill_schedule.csv")?;
    wtr.write_record(&[
        "Subject", "Start Date", "Start Time", "End Date", "End Time", "Location", "Description"
    ])?;

    for row in document.select(&row_selector) {
        let cells: Vec<_> = row.select(&cell_selector)
            .map(|c| c.text().collect::<String>().trim().to_string())
            .collect();

        if cells.len() >= 3 {
            let date = &cells[0];
            let opponent_raw = &cells[1];
            let time = &cells[2];

            let (subject, location, description) = if opponent_raw.contains("vs") {
                let opponent = opponent_raw.trim_start_matches("vs ").trim();
                (
                    format!("Fort Mill vs {}", opponent),
                    "Fort Mill High School",
                    "Home game"
                )
            } else if opponent_raw.contains("@") {
                let opponent = opponent_raw.trim_start_matches("@ ").trim();
                (
                    format!("Fort Mill @ {}", opponent),
                    opponent,
                    "Away game"
                )
            } else {
                (
                    format!("Fort Mill vs {}", opponent_raw),
                    "",
                    "Game"
                )
            };

            // Google Calendar requires both start and end date/time
            wtr.write_record(&[
                &subject,
                date,
                time,
                date,
                "", // leave end time blank
                &location,
                &description
            ])?;
        }
    }

    wtr.flush()?;
    println!("✅ Wrote schedule to fort_mill_schedule.csv");
    Ok(())
}
