#if 0  // Invoke with /bin/sh or simply add executable bit on this file on Unix.
B=${0%%.cc}; [ "$B" -nt "$0" ] || c++ -std=c++20 -Icnl/include -o"$B" "$0" && exec "$B" "$@";
#endif
/* -*- mode: c++; c-basic-offset: 2; indent-tabs-mode: nil; -*- */

// Calculate polynomials iteratively using only addition operations and fixed
// memory. Essentially Babbage's difference engine algorithm.
// Rediscovered by the authors over a coffee at CCC 2023.

//
/*
 * Plot output (./iterative-polynomial-sampler.cc > out.data) e.g. with gnuplot

 ```
 set ylabel "Polynomial"; set y2label "Error Percent"
 set y2range [-0.5:0.5] ; set y2tics 0.1 ; set ytics nomirror
 # Draw sampled polynomial, _actual_ polynomial and error of the sample
 plot "out.data" with lines, "" using 1:3 with lines, "" using 1:5 axes x1y2
````
*/

// If fixed point enabled, check out https://github.com/johnmcfarlane/cnl.git
// in cnl/ subdirectory.
#define USE_FIXED_POINT 0

#include <array>
#include <cmath>
#include <iostream>

#if USE_FIXED_POINT
#include "cnl/scaled_integer.h"
#endif

// === Types ===

// The polynomial coefficients are represented in somewhat high resolution
// as we don't want to loose precision in the one-time preparation.
using hires_number_t = double;

// The register number representation is typically chosen to be compact and
// fast to calculate. Ideally fixed point, for use in e.g. ASICs or FPGAs.
// All operations are simple additions, so fixed point is a neat
// representation.

#if USE_FIXED_POINT
// A fixed-point with <32>.<32> bits
using register_number_t = cnl::scaled_integer<int64_t, cnl::power<-32>>;
#else
using register_number_t = float;
#endif

// Representation of a polynomial of degree N.
// Initialized with coefficients 0 (constant), 1 (x), 2 (x^2) ... N (x^N)
//
// Provides evaluation operator().
template <int N, typename poly_real_t = double> class Polynomial {
public:
  Polynomial(std::array<poly_real_t, N + 1> coefficients)
      : coefficients_(coefficients) {}

  // Evaluate polynomial at x.
  poly_real_t operator()(poly_real_t x) const {
    poly_real_t result = coefficients_[0];
    for (int i = 1; i < N + 1; ++i) {
      result += coefficients_[i] * std::pow(x, i);
    }
    return result;
  }

private:
  const std::array<poly_real_t, N + 1> coefficients_;
};

// Polynomial sequential difference-engine sampler.
//
// This polynomial has a state stored in N+1 registers; it is initialized once
// using the desired starting `x` and `dx` value.
// Each Next() call returns the p(n + 1) value.
//
// We have two types.
//   * poly_real_t
//     The number the polynomial coefficients are represented and
//     prepared in (typically hi-resolution as this is a one-off operation and
//     to minimize initial error).
//
//     The "poly_real_t" type needs to allow multiplication, std::pow() and
//     addition. Also conversion into "register_number_t".
//
//   * register_number_t
//     The result type of the polynomial evaluated by this Sampler, also the
//     type the registers store to keep state.
//
//     Can be a simpler type, it only needs to allow addition.
//     Resolution can be chosen to best fit range and memory requirements.
//
//     The "register_number_t" type needs to allow addition.
template <int N, typename register_number_t = double>
class IterativePolynomialSampler {
public:
  // "p" the polynomial to be sampled. "x" starting point. "dx" steps between
  // Next() calls.
  template <typename poly_real_t>
  constexpr IterativePolynomialSampler(const Polynomial<N, poly_real_t> &p,
                                       const poly_real_t x,
                                       const poly_real_t dx) {
    std::array<poly_real_t, N + 1> hi_res_registers;
    // Fill the array with p(x - N - 1), p(x - N - 1 + dx) , p(x - N - 1 + 2dx),
    // etc...
    for (int i = 0; i < N + 1; ++i) {
      hi_res_registers[i] = p(x + (i - N - 1) * dx);
    }

    // Compute the differences in place.
    for (int i = 0; i < N; ++i) {
      for (int j = 0; j < N - i; ++j) {
        hi_res_registers[j] = hi_res_registers[j + 1] - hi_res_registers[j];
      }
    }

    // After accurate calcluation, fill the registers in the target resolution.
    for (int i = 0; i <= N; ++i) {
      registers_[i] = hi_res_registers[i];
    }
  }

  // Calculate the next value of the polynomial, "dx" away from the last x.
  register_number_t Next() {
    for (int i = 0; i < N; ++i) {
      registers_[i + 1] += registers_[i];  // NB: data dependency length N
    }
    return registers_[N];
  }

private:
  std::array<register_number_t, N + 1> registers_;
};

int main(int, char *[]) {
  constexpr int N = 3; // Degree of our sample polynomial.

  // ---------- coefficients for our polynomial ---->      c  x   x^2   x^3 ...
  const std::array<hires_number_t, N + 1> kCoeffcients = {-7, 10, -0.8, 0.01};
  const Polynomial<N, hires_number_t> p(kCoeffcients);

  constexpr hires_number_t kX  = 3;     // Start X position
  constexpr hires_number_t kDx = 0.1;   // Calulate in these dx steps
  constexpr int kNumSamples    = 1000;  // Calculate for this many steps.

  // Iterative sampler with chosen register number representation.
  IterativePolynomialSampler<N, register_number_t> s(p, kX, kDx);

  fprintf(stderr,
          "Register number representation: %d bytes; hi-res polynomial "
          "coefficient size: %d bytes\n",
          (int)sizeof(register_number_t), (int)sizeof(hires_number_t));
  fprintf(stderr, "%3s\t%12s\t%12s\t%10s\t%s\n", "x", "iterative", "actual",
          "error", "err%");
  for (int i = 0; i < kNumSamples; ++i) {
    const hires_number_t x = kX + i * kDx;

    const register_number_t iterative_result = s.Next();
    const hires_number_t actual_result = p(x);

    // How far are we off ?
    const hires_number_t error =
        (hires_number_t)iterative_result - actual_result;
    const double error_percent = 100.0 * error / actual_result; // from absolute

    // Here, we cast them to double or long double that the format string always
    // works
    fprintf(stdout, "%3.1f\t%12.6f\t%12.6f\t%10Lg\t%.5f\n", (double)x,
            (double)iterative_result, (double)actual_result, (long double)error,
            (double)error_percent);
  }

  return 0;
}
