use std::io;
use std::{thread, time::Duration};

fn main() {
    //greeting
    println!("Hiya! \nThis is a temp converter. Follow the prompts and you'll be on your way!");

    //ask
    println!("Enter the number you'd like to convert");

    //input 
    let mut num= String::new();
    io::stdin().read_line(&mut num).expect("couldn't get that number sorry");
    let num: f32 = num.trim().parse().expect("couldnt parse it");

    //validationc    
    print!("\nOkay - {num}\n");

    //pause
    thread::sleep(Duration::from_secs(2));

    //ask
    println!("Now enter the scale to convert to: (C or F)");

    //input
    let scale = String::new()
    io::stdin().read_line(&mut scale).expect("sorry couldn't get that scale");
    let scale: char = scale.trim().chars().nth().to_lowercase().expect("failed trim"); 
    
    //validationc    
    print!("\nOkay - to  {scale}\n");

    //pause
    thread::sleep(Duration::from_secs(2));

    //formula statements
    const SCALE_QUOTIENT: f32 = 9.0/5.0;
    const SCALE_NUM: i8= 32;

    //conversion expression
    if 
    //outro
}
