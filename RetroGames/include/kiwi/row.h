/*-----------------------------------------------------------------------------
| Copyright (c) 2013-2026, Nucleic Development Team.
|
| Distributed under the terms of the Modified BSD License.
|
| The full license is in the file LICENSE, distributed with this software.
|----------------------------------------------------------------------------*/
#pragma once
#include <algorithm>
#include <vector>
#include "platform.h"
#include "symbol.h"
#include "util.h"

namespace kiwi
{

namespace impl
{

// SoA (Structure-of-Arrays) row representation for the simplex tableau.
// Keys (Symbols) and values (coefficients) are stored in separate contiguous
// arrays, sorted by Symbol. This layout enables:
//   - Binary search on a dense key array (better cache utilization)
//   - SIMD bulk operations on the contiguous coefficient array
//   - Accelerate framework vDSP calls for scalar multiply, negate, FMA
class Row
{

public:

    // Lightweight proxy returned by the zip iterator for compatibility
    // with existing `for (const auto &cellPair : row.cells())` loops.
    struct CellRef
    {
        const Symbol &first;
        const double &second;
    };

    struct MutableCellRef
    {
        const Symbol &first;
        double &second;
    };

    class const_iterator
    {
    public:
        const_iterator(const Symbol *k, const double *v) : m_key(k), m_val(v) {}
        CellRef operator*() const { return {*m_key, *m_val}; }
        const_iterator &operator++() { ++m_key; ++m_val; return *this; }
        bool operator!=(const const_iterator &o) const { return m_key != o.m_key; }
        bool operator==(const const_iterator &o) const { return m_key == o.m_key; }
    private:
        const Symbol *m_key;
        const double *m_val;
    };

    class iterator
    {
    public:
        iterator(const Symbol *k, double *v) : m_key(k), m_val(v) {}
        MutableCellRef operator*() const { return {*m_key, *m_val}; }
        iterator &operator++() { ++m_key; ++m_val; return *this; }
        bool operator!=(const iterator &o) const { return m_key != o.m_key; }
        bool operator==(const iterator &o) const { return m_key == o.m_key; }
    private:
        const Symbol *m_key;
        double *m_val;
    };

    // Range adapter for the cells, compatible with range-for.
    class CellRange
    {
    public:
        CellRange(const Symbol *kb, const Symbol *ke, const double *vb)
            : m_kb(kb), m_ke(ke), m_vb(vb) {}
        const_iterator begin() const { return {m_kb, m_vb}; }
        const_iterator end() const { return {m_ke, m_vb + (m_ke - m_kb)}; }
        bool empty() const { return m_kb == m_ke; }
        std::size_t size() const { return static_cast<std::size_t>(m_ke - m_kb); }
    private:
        const Symbol *m_kb;
        const Symbol *m_ke;
        const double *m_vb;
    };

    class MutableCellRange
    {
    public:
        MutableCellRange(const Symbol *kb, const Symbol *ke, double *vb)
            : m_kb(kb), m_ke(ke), m_vb(vb) {}
        iterator begin() const { return {m_kb, m_vb}; }
        iterator end() const { return {m_ke, m_vb + (m_ke - m_kb)}; }
    private:
        const Symbol *m_kb;
        const Symbol *m_ke;
        double *m_vb;
    };

    Row() : Row(0.0) {}

    Row(double constant) : m_constant(constant) {}

    Row(const Row &other) = default;

    Row(Row &&other) noexcept = default;

    Row &operator=(const Row &other) = default;

    Row &operator=(Row &&other) noexcept = default;

    ~Row() = default;

    CellRange cells() const
    {
        const Symbol *kb = m_keys.data();
        return {kb, kb + m_keys.size(), m_values.data()};
    }

    MutableCellRange mutableCells()
    {
        const Symbol *kb = m_keys.data();
        return {kb, kb + m_keys.size(), m_values.data()};
    }

    double constant() const
    {
        return m_constant;
    }

    std::size_t cellCount() const
    {
        return m_keys.size();
    }

    // Direct access to the contiguous coefficient array (for SIMD).
    double *valueData() { return m_values.data(); }
    const double *valueData() const { return m_values.data(); }

    // Direct access to the key array.
    const Symbol *keyData() const { return m_keys.data(); }

    KIWI_ALWAYS_INLINE
    double add(double value)
    {
        return m_constant += value;
    }

    // Reset for pool reuse.
    void reset(double constant)
    {
        m_keys.clear();
        m_values.clear();
        m_constant = constant;
    }

    KIWI_ALWAYS_INLINE
    void insert(const Symbol &symbol, double coefficient = 1.0)
    {
        const auto pos = lowerBound(symbol);
        if (pos < m_keys.size() && m_keys[pos] == symbol)
        {
            m_values[pos] += coefficient;
            if (nearZero(m_values[pos]))
                eraseAt(pos);
        }
        else
        {
            if (!nearZero(coefficient))
                insertAt(pos, symbol, coefficient);
        }
    }

    void insert(const Row &other, double coefficient = 1.0)
    {
        m_constant += other.m_constant * coefficient;
        const std::size_t n = other.m_keys.size();
        for (std::size_t i = 0; i < n; ++i)
        {
            const double coeff = other.m_values[i] * coefficient;
            const auto pos = lowerBound(other.m_keys[i]);
            if (pos < m_keys.size() && m_keys[pos] == other.m_keys[i])
            {
                m_values[pos] += coeff;
                if (nearZero(m_values[pos]))
                    eraseAt(pos);
            }
            else
            {
                if (!nearZero(coeff))
                    insertAt(pos, other.m_keys[i], coeff);
            }
        }
    }

    void remove(const Symbol &symbol)
    {
        const auto pos = lowerBound(symbol);
        if (pos < m_keys.size() && m_keys[pos] == symbol)
            eraseAt(pos);
    }

    void reverseSign()
    {
        m_constant = -m_constant;
        const std::size_t n = m_values.size();
#if KIWI_HAS_ACCELERATE
        if (n > 0)
        {
            vDSP_vnegD(m_values.data(), 1, m_values.data(), 1, static_cast<vDSP_Length>(n));
            return;
        }
#endif
        for (std::size_t i = 0; i < n; ++i)
            m_values[i] = -m_values[i];
    }

    void solveFor(const Symbol &symbol)
    {
        const auto pos = lowerBound(symbol);
        const double coeff = -1.0 / m_values[pos];
        eraseAt(pos);
        m_constant *= coeff;
        const std::size_t n = m_values.size();
#if KIWI_HAS_ACCELERATE
        if (n > 0)
        {
            vDSP_vsmulD(m_values.data(), 1, &coeff, m_values.data(), 1, static_cast<vDSP_Length>(n));
            return;
        }
#endif
        for (std::size_t i = 0; i < n; ++i)
            m_values[i] *= coeff;
    }

    void solveFor(const Symbol &lhs, const Symbol &rhs)
    {
        insert(lhs, -1.0);
        solveFor(rhs);
    }

    KIWI_ALWAYS_INLINE
    double coefficientFor(const Symbol &symbol) const
    {
        const auto pos = lowerBound(symbol);
        if (pos < m_keys.size() && m_keys[pos] == symbol)
            return m_values[pos];
        return 0.0;
    }

    void substitute(const Symbol &symbol, const Row &row)
    {
        const auto pos = lowerBound(symbol);
        if (pos < m_keys.size() && m_keys[pos] == symbol)
        {
            const double coefficient = m_values[pos];
            eraseAt(pos);
            insert(row, coefficient);
        }
    }

private:

    // Binary search on the key array. Returns the index where `symbol`
    // is or would be inserted.
    KIWI_ALWAYS_INLINE
    std::size_t lowerBound(const Symbol &symbol) const
    {
        return static_cast<std::size_t>(
            std::lower_bound(m_keys.begin(), m_keys.end(), symbol) - m_keys.begin());
    }

    void insertAt(std::size_t pos, const Symbol &symbol, double value)
    {
        m_keys.insert(m_keys.begin() + static_cast<std::ptrdiff_t>(pos), symbol);
        m_values.insert(m_values.begin() + static_cast<std::ptrdiff_t>(pos), value);
    }

    void eraseAt(std::size_t pos)
    {
        m_keys.erase(m_keys.begin() + static_cast<std::ptrdiff_t>(pos));
        m_values.erase(m_values.begin() + static_cast<std::ptrdiff_t>(pos));
    }

    std::vector<Symbol> m_keys;
    std::vector<double> m_values;
    double m_constant;
};

} // namespace impl

} // namespace kiwi
