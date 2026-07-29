import { firefox } from "playwright";
import { expect } from "playwright/test";
//https://www.linkedin.com/in/sharon-high-1127582/
const user = prompt("who are we connecting", "<link>");
const message = prompt("what would you like to say", "<message>");
const browser = await firefox.launch({ headless: false });
const page = await browser.newPage();

async function authenticate() {
  const loginURL = "https://www.linkedin.com/login/";
  await page.goto(loginURL);
}

async function connect() {
  await page.goto(user);
  await page.getByText("Connect", { exact: true }).click();
  await page.getByText("Add a note", { exact: true }).click();
}

authenticate();
connect();
