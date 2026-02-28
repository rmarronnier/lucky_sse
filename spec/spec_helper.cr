require "spec"
require "../src/lucky_sse"

def wait_until(timeout : Time::Span = 1.second, &block : -> Bool) : Bool
  deadline = Time.instant + timeout
  until block.call
    return false if Time.instant >= deadline
    sleep 5.milliseconds
  end
  true
end
