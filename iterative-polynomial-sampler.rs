//usr/bin/env true; B=${0%%.rs}_binrs; [ "$B" -nt "$0" ] || rustc -o"$B" "$0" && exec "$B" "$@"

// Transcript from the C++ program iterative-polynomial-sampler.cc, see there
// for details.

// === Types ===

type HiResNumber = f64; // High-resolution coefficient/setup type
type RegisterNumber = f32; // Compact, fast register type

// === Polynomial Struct ===

// N is the degree of the polynomial.
// N_PLUS_ONE is the total size of the coefficient array (N + 1).
struct Polynomial<const N: usize, const N_PLUS_ONE: usize> {
    coefficients: [HiResNumber; N_PLUS_ONE],
}

impl<const N: usize, const N_PLUS_ONE: usize> Polynomial<N, N_PLUS_ONE> {
    fn new(coefficients: [HiResNumber; N_PLUS_ONE]) -> Self {
        Polynomial { coefficients }
    }

    // Evaluate polynomial at x.
    fn eval(&self, x: HiResNumber) -> HiResNumber {
        let mut result = self.coefficients[0];
        for i in 1..=N {
            result += self.coefficients[i] * x.powi(i as i32);
        }
        result
    }
}

// === Sampler Struct ===

// IterativePolynomialSampler stores N+1 registers (differences and the current value).
struct IterativePolynomialSampler<const N: usize, const N_PLUS_ONE: usize> {
    registers: [RegisterNumber; N_PLUS_ONE],
}

impl<const N: usize, const N_PLUS_ONE: usize> IterativePolynomialSampler<N, N_PLUS_ONE> {
    // Constructor: Initializes registers with pre-calculated differences.
    fn new(p: &Polynomial<N, N_PLUS_ONE>, x: HiResNumber, dx: HiResNumber) -> Self {
        let mut hi_res_registers = [0.0; N_PLUS_ONE];

        // 1. Fill array with initial polynomial values required to calculate differences.
        for i in 0..N_PLUS_ONE {
            let offset = (i as i64) - (N as i64) - 1;
            hi_res_registers[i] = p.eval(x + (offset as HiResNumber) * dx);
        }

        // 2. Compute the differences in place.
        for i in 0..N {
            for j in 0..N - i {
                let new_diff = hi_res_registers[j + 1] - hi_res_registers[j];
                hi_res_registers[j] = new_diff;
            }
        }

        // 3. Cast to the target register resolution.
        let mut registers = [0.0; N_PLUS_ONE];
        for i in 0..N_PLUS_ONE {
            registers[i] = hi_res_registers[i] as RegisterNumber;
        }

        IterativePolynomialSampler { registers }
    }

    // Calculate the next value of the polynomial using only addition.
    fn next(&mut self) -> RegisterNumber {
        // Core iterative addition loop (data dependency length N)
        for i in 0..N {
            self.registers[i + 1] += self.registers[i];
        }
        // The last register holds the new polynomial value P(x+dx).
        self.registers[N]
    }
}

// === Main Function (Demonstration) ===

fn main() {
    const N: usize = 3;
    const N_PLUS_ONE: usize = N + 1; // Explicitly define the array size

    // Coefficients: c, x, x^2, x^3
    const K_COEFFICIENTS: [HiResNumber; N_PLUS_ONE] = [-7.0, 10.0, -0.8, 0.01];
    let p = Polynomial::<N, N_PLUS_ONE>::new(K_COEFFICIENTS);

    const K_X: HiResNumber = 3.0;       // Start X position
    const K_DX: HiResNumber = 0.1;      // Calulate in these dx steps
    const K_NUM_SAMPLES: usize = 1000;  // Calculate for this many steps.

    // Instantiate iterative sampler
    let mut s = IterativePolynomialSampler::<N, N_PLUS_ONE>::new(&p, K_X, K_DX);

    // Print headers to stderr
    eprintln!(
        "Register number representation: {} bytes; hi-res polynomial coefficient size: {} bytes",
        std::mem::size_of::<RegisterNumber>(),
        std::mem::size_of::<HiResNumber>()
    );
    eprintln!("{:3}\t{:12}\t{:12}\t{:10}\t{}", "x", "iterative", "actual", "error", "err%");

    // Loop through samples
    for i in 0..K_NUM_SAMPLES {
        let x = K_X + (i as HiResNumber) * K_DX;

        let iterative_result = s.next();
        let actual_result = p.eval(x);

        // Calculate errors
        let error = (iterative_result as HiResNumber) - actual_result;
        let error_percent = 100.0 * error / actual_result;

        // Print results to stdout
        println!(
            "{x:3.1}\t{iterative_result:12.6}\t{actual_result:12.6}\t{error:10.6}\t{error_percent:.5}",
            x = x,
            iterative_result = iterative_result,
            actual_result = actual_result,
            error = error,
            error_percent = error_percent
        );
    }
}
