#pragma once
#include "kiwi/kiwi.h"
#include <memory>

namespace kiwi_swift {

// Return-by-value accessors for methods that return const refs (blocked by Swift safety)
inline std::string getVariableName(const kiwi::Variable& var) {
    return var.name();  // copies the string
}

// Term accessors
inline kiwi::Variable getTermVariable(const kiwi::Term& term) {
    return term.variable();  // copies the Variable (lightweight, uses shared_ptr internally)
}

// Expression accessors
inline std::vector<kiwi::Term> getExpressionTerms(const kiwi::Expression& expr) {
    return expr.terms();  // copies the vector
}

// Constraint accessors
inline kiwi::Expression getConstraintExpression(const kiwi::Constraint& constraint) {
    return constraint.expression();  // copies the Expression
}

// Term builder for Swift (avoids std::vector template issues)
class ExpressionBuilder {
public:
    ExpressionBuilder() : m_constant(0.0) {}

    void addTerm(const kiwi::Variable& var, double coefficient) {
        m_terms.push_back(kiwi::Term(var, coefficient));
    }

    void setConstant(double constant) {
        m_constant = constant;
    }

    kiwi::Expression build() const {
        return kiwi::Expression(m_terms, m_constant);
    }

    kiwi::Constraint buildConstraint(kiwi::RelationalOperator op, double strength) const {
        return kiwi::Constraint(build(), op, strength);
    }

private:
    std::vector<kiwi::Term> m_terms;
    double m_constant;
};

// Constraint builders for Swift (avoiding operator overloading issues)
struct ConstraintBuilder {
    // === Single variable constraints ===

    // Variable == constant
    static kiwi::Constraint equalTo(const kiwi::Variable& var, double constant, double strength = kiwi::strength::required) {
        return kiwi::Constraint(kiwi::Expression(kiwi::Term(var), -constant), kiwi::OP_EQ, strength);
    }

    // Variable >= constant
    static kiwi::Constraint greaterOrEqual(const kiwi::Variable& var, double constant, double strength = kiwi::strength::required) {
        return kiwi::Constraint(kiwi::Expression(kiwi::Term(var), -constant), kiwi::OP_GE, strength);
    }

    // Variable <= constant
    static kiwi::Constraint lessOrEqual(const kiwi::Variable& var, double constant, double strength = kiwi::strength::required) {
        return kiwi::Constraint(kiwi::Expression(kiwi::Term(var), -constant), kiwi::OP_LE, strength);
    }

    // === Two variable constraints ===

    // var1 == var2
    static kiwi::Constraint equal(const kiwi::Variable& var1, const kiwi::Variable& var2, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, 1.0), kiwi::Term(var2, -1.0)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), 0.0), kiwi::OP_EQ, strength);
    }

    // var1 >= var2
    static kiwi::Constraint greaterOrEqualVar(const kiwi::Variable& var1, const kiwi::Variable& var2, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, 1.0), kiwi::Term(var2, -1.0)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), 0.0), kiwi::OP_GE, strength);
    }

    // var1 <= var2
    static kiwi::Constraint lessOrEqualVar(const kiwi::Variable& var1, const kiwi::Variable& var2, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, 1.0), kiwi::Term(var2, -1.0)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), 0.0), kiwi::OP_LE, strength);
    }

    // var1 == var2 + offset
    static kiwi::Constraint equalWithOffset(const kiwi::Variable& var1, const kiwi::Variable& var2, double offset, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, 1.0), kiwi::Term(var2, -1.0)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), -offset), kiwi::OP_EQ, strength);
    }

    // var1 >= var2 + offset
    static kiwi::Constraint greaterOrEqualWithOffset(const kiwi::Variable& var1, const kiwi::Variable& var2, double offset, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, 1.0), kiwi::Term(var2, -1.0)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), -offset), kiwi::OP_GE, strength);
    }

    // var1 <= var2 + offset
    static kiwi::Constraint lessOrEqualWithOffset(const kiwi::Variable& var1, const kiwi::Variable& var2, double offset, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, 1.0), kiwi::Term(var2, -1.0)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), -offset), kiwi::OP_LE, strength);
    }

    // === Sum constraints ===

    // var1 + var2 == constant
    static kiwi::Constraint sumEqual(const kiwi::Variable& var1, const kiwi::Variable& var2, double constant, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, 1.0), kiwi::Term(var2, 1.0)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), -constant), kiwi::OP_EQ, strength);
    }

    // var1 + var2 >= constant
    static kiwi::Constraint sumGreaterOrEqual(const kiwi::Variable& var1, const kiwi::Variable& var2, double constant, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, 1.0), kiwi::Term(var2, 1.0)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), -constant), kiwi::OP_GE, strength);
    }

    // var1 + var2 <= constant
    static kiwi::Constraint sumLessOrEqual(const kiwi::Variable& var1, const kiwi::Variable& var2, double constant, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, 1.0), kiwi::Term(var2, 1.0)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), -constant), kiwi::OP_LE, strength);
    }

    // === Linear combination constraints ===

    // coef1*var1 + coef2*var2 == constant
    static kiwi::Constraint linearEqual(const kiwi::Variable& var1, double coef1,
                                        const kiwi::Variable& var2, double coef2,
                                        double constant, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, coef1), kiwi::Term(var2, coef2)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), -constant), kiwi::OP_EQ, strength);
    }

    // coef1*var1 + coef2*var2 >= constant
    static kiwi::Constraint linearGreaterOrEqual(const kiwi::Variable& var1, double coef1,
                                                  const kiwi::Variable& var2, double coef2,
                                                  double constant, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, coef1), kiwi::Term(var2, coef2)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), -constant), kiwi::OP_GE, strength);
    }

    // coef1*var1 + coef2*var2 <= constant
    static kiwi::Constraint linearLessOrEqual(const kiwi::Variable& var1, double coef1,
                                               const kiwi::Variable& var2, double coef2,
                                               double constant, double strength = kiwi::strength::required) {
        std::vector<kiwi::Term> terms = {kiwi::Term(var1, coef1), kiwi::Term(var2, coef2)};
        return kiwi::Constraint(kiwi::Expression(std::move(terms), -constant), kiwi::OP_LE, strength);
    }
};

// Error codes for Swift
enum class SolverError : int {
    None = 0,
    UnsatisfiableConstraint = 1,
    UnknownConstraint = 2,
    DuplicateConstraint = 3,
    UnknownEditVariable = 4,
    DuplicateEditVariable = 5,
    BadRequiredStrength = 6,
    InternalError = 7
};

// Result type for operations that can fail
struct SolverResult {
    SolverError error = SolverError::None;
    std::string message;

    bool ok() const { return error == SolverError::None; }

    static SolverResult success() { return SolverResult{}; }

    static SolverResult fromError(SolverError err, const char* msg) {
        SolverResult r;
        r.error = err;
        r.message = msg;
        return r;
    }
};

// Swift-friendly Solver (wraps kiwi::Solver which isn't directly importable)
class Solver {
public:
    Solver() : m_solver(std::make_unique<kiwi::Solver>()) {}

    // Non-throwing versions that return results
    SolverResult addConstraint(const kiwi::Constraint& constraint) {
        try {
            m_solver->addConstraint(constraint);
            return SolverResult::success();
        } catch (const kiwi::UnsatisfiableConstraint& e) {
            return SolverResult::fromError(SolverError::UnsatisfiableConstraint, e.what());
        } catch (const kiwi::DuplicateConstraint& e) {
            return SolverResult::fromError(SolverError::DuplicateConstraint, e.what());
        } catch (const std::exception& e) {
            return SolverResult::fromError(SolverError::InternalError, e.what());
        }
    }

    SolverResult removeConstraint(const kiwi::Constraint& constraint) {
        try {
            m_solver->removeConstraint(constraint);
            return SolverResult::success();
        } catch (const kiwi::UnknownConstraint& e) {
            return SolverResult::fromError(SolverError::UnknownConstraint, e.what());
        } catch (const std::exception& e) {
            return SolverResult::fromError(SolverError::InternalError, e.what());
        }
    }

    bool hasConstraint(const kiwi::Constraint& constraint) const {
        return m_solver->hasConstraint(constraint);
    }

    SolverResult addEditVariable(const kiwi::Variable& variable, double strength) {
        try {
            m_solver->addEditVariable(variable, strength);
            return SolverResult::success();
        } catch (const kiwi::DuplicateEditVariable& e) {
            return SolverResult::fromError(SolverError::DuplicateEditVariable, e.what());
        } catch (const kiwi::BadRequiredStrength& e) {
            return SolverResult::fromError(SolverError::BadRequiredStrength, e.what());
        } catch (const std::exception& e) {
            return SolverResult::fromError(SolverError::InternalError, e.what());
        }
    }

    SolverResult removeEditVariable(const kiwi::Variable& variable) {
        try {
            m_solver->removeEditVariable(variable);
            return SolverResult::success();
        } catch (const kiwi::UnknownEditVariable& e) {
            return SolverResult::fromError(SolverError::UnknownEditVariable, e.what());
        } catch (const std::exception& e) {
            return SolverResult::fromError(SolverError::InternalError, e.what());
        }
    }

    bool hasEditVariable(const kiwi::Variable& variable) const {
        return m_solver->hasEditVariable(variable);
    }

    SolverResult suggestValue(const kiwi::Variable& variable, double value) {
        try {
            m_solver->suggestValue(variable, value);
            return SolverResult::success();
        } catch (const kiwi::UnknownEditVariable& e) {
            return SolverResult::fromError(SolverError::UnknownEditVariable, e.what());
        } catch (const std::exception& e) {
            return SolverResult::fromError(SolverError::InternalError, e.what());
        }
    }

    void updateVariables() {
        m_solver->updateVariables();
    }

    void reset() {
        m_solver->reset();
    }

private:
    std::unique_ptr<kiwi::Solver> m_solver;
};

// Strength constants for Swift
struct Strength {
    static double required() { return kiwi::strength::required; }
    static double strong() { return kiwi::strength::strong; }
    static double medium() { return kiwi::strength::medium; }
    static double weak() { return kiwi::strength::weak; }

    static double create(double a, double b, double c, double w = 1.0) {
        return kiwi::strength::create(a, b, c, w);
    }
};

} // namespace kiwi_swift
