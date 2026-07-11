use std::error::Error;
use std::fs::File;
use std::io::{BufReader, BufWriter};
use csv::{ReaderBuilder, WriterBuilder, StringRecord};
use regex::Regex;

fn main() -> Result<(), Box<dyn Error>> {
    let input = File::open("googlecontacts.csv")?;
    let output = File::create("googlecontacts_fixed.csv")?;

    let mut reader = ReaderBuilder::new()
        .has_headers(true)
        .from_reader(BufReader::new(input));

    let headers = reader.headers()?.clone();
    let mut writer = WriterBuilder::new()
        .has_headers(true)
        .from_writer(BufWriter::new(output));

    writer.write_record(&headers)?;

    let re = Regex::new(r"Other:\s*(\+1\d{10})")?;

    for result in reader.records() {
        let record = result?;
        let mut fields: Vec<String> = record.iter().map(|s| s.to_string()).collect();

        let notes_index = headers.iter().position(|h| h == "Notes").unwrap();
        let mobile_index = headers.iter().position(|h| h == "Phone 1 - Value").unwrap();

        let notes = &fields[notes_index];
        let mobile = &fields[mobile_index];

        if mobile.trim().is_empty() {
            if let Some(caps) = re.captures(notes) {
                if let Some(phone) = caps.get(1) {
                    fields[mobile_index] = phone.as_str().to_string();
                }
            }
        }

        writer.write_record(&StringRecord::from(fields))?;
    }

    println!("Finished processing. Output saved to googlecontacts_fixed.csv");
    Ok(())
}
