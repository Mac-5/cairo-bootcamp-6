#[executable]
fn main() {
    let result: bool = is_adult(18);
    println!("bool result = {}", result);

     let is_even_result: bool = is_even(17);
    println!("result = {}", is_even_result);
}

// determine boolean for adults
fn is_adult(x: u8) -> bool {
    // let mut outcome: bool = false;
    if x <= 18 {
        // outcome = false;
        return false;
    }
    // outcome = true;
    return true;
}


// determine even numbers
fn is_even(x: u8) -> bool {
    if x % 2 == 0 {
        return true;
    } 
    return false;
}

