// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice A single point in an unlock schedule using absolute timestamps
/// @dev The proportion is stored as a uint64 to avoid overflows and fit into a single storage slot.
/// @dev Uses absolute timestamps (block.timestamp) to enforce the unlock schedule at specific points in time
struct ScheduleAbsolutePoint {
    uint64 timestamp; // Absolute block timestamp for this unlock point
    uint64 proportionNumerator; // Numerator of the proportion (e.g., 25 for 25/100 = 25%)
    uint64 proportionDenominator; // Denominator of the proportion (e.g., 100 for 25/100 = 25%)
}

/// @notice Complete unlock schedule configuration using absolute timestamps for the unlock points.
struct UnlockAbsoluteSchedule {
    ScheduleAbsolutePoint[] points; // Array of unlock points (must be time-ordered)
    bytes6[] interpolationTypes; // Interpolation types between each consecutive pair of points. This should always be points.length - 1.
}

/// @notice Library for handling different unlock schedule interpolation types
library ScheduleTypes {
    error NoUnlockSchedulePoints();
    error InvalidInterpolationCount();
    error TimestampCannotBeZero();
    error ProportionDenominatorCannotBeZero();
    error ProportionCannotExceedOne();
    error SchedulePointsMustBeSortedByTime();
    error ProportionsMustBeMonotonicallyIncreasing();
    error LastPointMustHaveProportionOfOne();
    error InvalidInterpolationType(bytes6);
    error InvalidUnlockSchedule();
    error InvalidCurrentTime(uint64);

    /// @notice Interpolation type identifiers for unlock schedules
    /// EXISTING TYPES MUST NOT BE CHANGED!
    bytes6 constant CONSTANT = bytes6(keccak256("CONSTANT"));
    bytes6 constant LINEAR = bytes6(keccak256("LINEAR"));

    /// @notice Validates an unlock schedule
    /// @param schedule The schedule to validate
    /// @dev Reverts with specific error type if validation fails
    function validateSchedule(UnlockAbsoluteSchedule memory schedule) internal pure {
        if (schedule.points.length == 0) {
            revert NoUnlockSchedulePoints();
        }

        if (schedule.points.length != schedule.interpolationTypes.length + 1) {
            revert InvalidInterpolationCount();
        }

        // Validate interpolation types
        for (uint256 i = 0; i < schedule.interpolationTypes.length; i++) {
            bytes6 interpolationType = schedule.interpolationTypes[i];
            // Validate against known interpolation types
            if (interpolationType != CONSTANT && interpolationType != LINEAR) {
                revert InvalidInterpolationType(interpolationType);
            }
        }

        // Check points are properly ordered and proportions are valid
        for (uint256 i = 0; i < schedule.points.length; i++) {
            ScheduleAbsolutePoint memory point = schedule.points[i];

            if (point.timestamp == 0) {
                revert TimestampCannotBeZero();
            }

            if (point.proportionDenominator == 0) {
                revert ProportionDenominatorCannotBeZero();
            }

            // Check proportion is <= 1 (numerator <= denominator)
            if (point.proportionNumerator > point.proportionDenominator) {
                revert ProportionCannotExceedOne();
            }

            // Check time and proportion ordering (must be monotonically increasing)
            if (i > 0) {
                ScheduleAbsolutePoint memory prevPoint = schedule.points[i - 1];

                // Timestamps must be monotonically increasing
                if (point.timestamp < prevPoint.timestamp) {
                    revert SchedulePointsMustBeSortedByTime();
                }

                // Compare proportions: point.num/point.denom >= prevPoint.num/prevPoint.denom
                // Equivalent to: point.num * prevPoint.denom >= prevPoint.num * point.denom
                if (
                    point.proportionNumerator * prevPoint.proportionDenominator
                        < prevPoint.proportionNumerator * point.proportionDenominator
                ) {
                    revert ProportionsMustBeMonotonicallyIncreasing();
                }
            }

            // Last point must have proportion of exactly 1
            if (i == schedule.points.length - 1) {
                if (point.proportionNumerator != point.proportionDenominator) {
                    revert LastPointMustHaveProportionOfOne();
                }
            }
        }
    }

    /// @notice Calculates the amount of tokens unlocked at a specific time
    /// @dev Assumes that the schedule has been validated before running the calculation
    /// @param schedule The unlock schedule
    /// @param totalTokens Total number of tokens to be unlocked
    /// @param currentTime Current timestamp
    /// @return unlockedTokens Number of tokens unlocked at the current time
    function calculateUnlockedTokens(UnlockAbsoluteSchedule storage schedule, uint256 totalTokens, uint64 currentTime)
        internal
        view
        returns (uint256 unlockedTokens)
    {
        ScheduleAbsolutePoint[] storage points = schedule.points;
        bytes6[] storage interpolationTypes = schedule.interpolationTypes;
        uint256 pointsLength = points.length;

        // If current time is before the first point, no tokens are unlocked
        if (currentTime < points[0].timestamp) {
            return 0;
        }

        // If current time is after or equal to the last point, all tokens are unlocked
        if (currentTime >= points[pointsLength - 1].timestamp) {
            return totalTokens;
        }

        // Find the two points that currentTime falls between using binary search
        uint256 intervalIndex = _findIntervalIndex(points, currentTime);

        ScheduleAbsolutePoint storage prevPoint = points[intervalIndex];
        ScheduleAbsolutePoint storage nextPoint = points[intervalIndex + 1];
        bytes6 interpolationType = interpolationTypes[intervalIndex];

        if (interpolationType == CONSTANT) {
            return _interpolateConstant(totalTokens, prevPoint);
        }

        if (interpolationType == LINEAR) {
            return _interpolateLinear(totalTokens, currentTime, prevPoint, nextPoint);
        }
        revert InvalidInterpolationType(interpolationType);
    }

    function _interpolateConstant(uint256 totalTokens, ScheduleAbsolutePoint memory prevPoint)
        internal
        pure
        returns (uint256)
    {
        return Math.mulDiv(totalTokens, prevPoint.proportionNumerator, prevPoint.proportionDenominator);
    }

    function _interpolateLinear(
        uint256 totalTokens,
        uint64 currentTime,
        ScheduleAbsolutePoint memory prevPoint,
        ScheduleAbsolutePoint memory nextPoint
    ) internal pure returns (uint256) {
        // Enforce that the current time is within the bounds of the two points. This should not happen as the logic is intended to be used in the calculation
        // function and should not be called directly, but we include this check here to ensure that the the parameters are valid.
        if (currentTime >= nextPoint.timestamp || currentTime < prevPoint.timestamp) {
            revert InvalidCurrentTime(currentTime);
        }

        // For linear interpolation, interpolate between the previous and next point
        uint256 totalDuration = nextPoint.timestamp - prevPoint.timestamp;
        uint256 elapsedDuration = currentTime - prevPoint.timestamp;

        // Calculate interpolation factor
        // lambda = elapsedDuration / totalDuration
        // interpolatedFactor = lambda * (nextFactor  - previousFactor) + previousFactor
        //
        // interpolatedNum / interpolatedDenom
        // = elapsedDuration / totalDuration * (nextNum / nextDenom - prevNum / prevDenom) + prevNum / prevDenom
        // = elapsedDuration / totalDuration * (nextNum * prevDenom - prevNum * nextDenom) / (nextDenom  * prevDenom) + prevNum / prevDenom
        // = (elapsedDuration * (nextNum * prevDenom - prevNum * nextDenom) + prevNum * nextDenom * totalDuration) / (nextDenom  * prevDenom * totalDuration)
        //
        // ->
        // interpolatedNum = elapsedDuration * (nextNum * prevDenom - prevNum * nextDenom) + prevNum * nextDenom * totalDuration
        // interpolatedDenom = nextDenom  * prevDenom * totalDuration
        //
        // where:
        // commonDenominator = nextDenom * prevDenom
        // prevNumeratorNormalized = prevNum * nextDenom
        // nextNumeratorNormalized = nextNum * prevDenom
        //
        // hence we get:
        // interpolatedNum = elapsedDuration * (nextNumeratorNormalized - prevNumeratorNormalized) + prevNumeratorNormalized * totalDuration
        // interpolatedDenom = commonDenominator * totalDuration

        // First normalize proportions to the same denominator
        uint256 commonDenominator = uint256(prevPoint.proportionDenominator) * uint256(nextPoint.proportionDenominator);
        uint256 prevNumeratorNormalized =
            uint256(prevPoint.proportionNumerator) * uint256(nextPoint.proportionDenominator);
        uint256 nextNumeratorNormalized =
            uint256(nextPoint.proportionNumerator) * uint256(prevPoint.proportionDenominator);

        // Calculate the interpolated numerator
        uint256 proportionDiff = nextNumeratorNormalized - prevNumeratorNormalized;
        // progressNumerator is equivalent to: elapsedDuration * (nextNumeratorNormalized - prevNumeratorNormalized)
        uint256 progressNumerator = proportionDiff * elapsedDuration;

        uint256 unlockedRatioNumerator = progressNumerator + prevNumeratorNormalized * totalDuration;
        uint256 unlockedRatioDenominator = commonDenominator * totalDuration;
        return Math.mulDiv(totalTokens, unlockedRatioNumerator, unlockedRatioDenominator);
    }

    /// @notice Finds the interval index where currentTime falls between points[i] and points[i+1]
    /// @dev Uses binary search to find the largest index i such that points[i].timestamp <= currentTime < points[i+1].timestamp
    /// @dev Assumes points are sorted by timestamp and currentTime is within the valid range
    /// @param points Array of schedule points (must be sorted by timestamp)
    /// @param currentTime Current timestamp to find interval for
    /// @return intervalIndex The index i where points[i].timestamp <= currentTime < points[i+1].timestamp
    function _findIntervalIndex(ScheduleAbsolutePoint[] storage points, uint64 currentTime)
        internal
        view
        returns (uint256 intervalIndex)
    {
        uint256 pointsLength = points.length;
        uint256 left = 0;
        uint256 right = pointsLength - 1;

        // We check a set of defensive invariants to ensure that the parameters are valid before proceeding through the binary search, these checks should
        // never fails as the validation functions should be called before calling this function.
        //
        // We always assume that the schedule has at least two points.
        assert(points.length > 1);
        // The current time should be within the bounds of the points, inclusive of the left and exclusive of the right: [leftTimestamp, rightTimestamp)
        assert(points[left].timestamp <= currentTime && currentTime < points[right].timestamp);

        // Binary search for the rightmost point where timestamp <= currentTime
        // Use upper mid to avoid infinite loop
        while (left < right) {
            uint256 mid = left + (right - left + 1) / 2;

            if (points[mid].timestamp <= currentTime) {
                left = mid;
                continue;
            }
            right = mid - 1;
        }

        // At this point, left == right and points[left].timestamp <= currentTime
        // We need to ensure that left < points.length - 1 so that points[left + 1] exists
        if (left >= pointsLength - 1) {
            revert InvalidUnlockSchedule();
        }

        return left;
    }
}
